dnl Process this m4 file to produce 'C' language file.
dnl
dnl If you see this line, you can ignore the next one.
/* Do not edit this file. It is produced from the corresponding .m4 source */
dnl
/*
 *  Copyright (C) 2014, Northwestern University and Argonne National Laboratory
 *  See COPYRIGHT notice in top-level directory.
 */
/* $Id$ */

/*
 * This file implements the corresponding APIs defined in
 * src/dispatchers/var_getput.m4
 *
 * ncmpi_iget_varn_<type>() : dispatcher->iget_varn()
 * ncmpi_iput_varn_<type>() : dispatcher->iput_varn()
 * ncmpi_bput_varn_<type>() : dispatcher->bput_varn()
 */

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include <stdio.h>
#include <unistd.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <string.h> /* memcpy() */
#include <limits.h> /* INT_MAX */
#include <assert.h>

#include <mpi.h>

#include <pnc_debug.h>
#include <common.h>
#include "ncmpio_NC.h"

/*----< igetput_varn() >-----------------------------------------------------*/
/* The implementation of nonlocking varn APIs is to add "num" iget/iput
 * requests to the nonblocking request queue. These requests may be flattened
 * and sorted together with other nonblocking requests during the wait call.
 * All the "num" nonblocking requests posted by iget/iput/bput_varn() share
 * the same request ID.
 */
static int
igetput_varn(NC                *ncp,
             NC_var            *varp,
             int                num,
             MPI_Offset* const *starts,  /* [num][varp->ndims] */
             MPI_Offset* const *counts,  /* [num][varp->ndims] */
             void              *buf,
             MPI_Offset         bufcount,
             MPI_Datatype       buftype,   /* data type of the bufer */
             int               *reqidp,    /* OUT: request ID */
             int                reqMode)
{
    int i, j, err, free_xbuf=0, reqid, isize, xsize, abuf_index=-1, max_nreqs;
    int isContig=1, need_convert, need_swap, need_swap_back_buf=0;
    size_t memChunk;
    void *xbuf=NULL;
    char *xbufp;
    MPI_Offset nelems, nbytes, *start_ptr;
    MPI_Datatype itype, xtype;
    NC_req *req;

    /* if called from a bput API, check if buffer has been attached */
    if (fIsSet(reqMode, NC_REQ_NBB) && ncp->abuf == NULL)
        DEBUG_RETURN_ERROR(NC_ENULLABUF)

    /* validity of starts and counts has been checked at dispatcher layer */

    /* calculate nelems and max_nreqs */
    if (counts != NULL) {
        /* nelems will be the total number of array elements of this varn */
        nelems = 0;
        max_nreqs = 0;
        for (j=0; j<num; j++) {
            MPI_Offset nlen = 1;
            for (i=0; i<varp->ndims; i++)
                nlen *= counts[j][i];
            nelems += nlen;

            /* calculate the max number of requests to be added to queue */
            if (IS_RECVAR(varp)) /* each record will be a separate request */
                max_nreqs += counts[j][0];
            else
                max_nreqs++;
        }
    }
    else { /* when counts == NULL, it means all counts[] are 1s */
        nelems = num;
        max_nreqs = num;
    }

    /* xtype is the MPI element type in external representation, xszie is its
     * size in bytes. Similarly, itype and isize for internal representation.
     */
    xtype = ncmpii_nc2mpitype(varp->xtype);
    MPI_Type_size(xtype, &xsize);

    if (buftype == MPI_DATATYPE_NULL) {
	/* In this case, bufcount is ignored and the internal buffer data type
	 * match the external variable data type. No data conversion will be
	 * done. In addition, it means buf is contiguous. Hereinafter, buftype
         * is ignored.
         */
        itype = xtype;
        isize = xsize;
    }
    else if (bufcount == -1) { /* buftype is an MPI primitive data type */
        /* In this case, this subroutine is called from a high-level API.
         * buftype is one of the MPI primitive data type. We set itype to
         * buftype. itype is the MPI element type in internal representation.
         * In addition, it means the user buf is contiguous.
         */
        itype = buftype;
        MPI_Type_size(itype, &isize); /* buffer element size */
    }
    else { /* (bufcount > 0) */
        /* When bufcount > 0, this subroutine is called from a flexible API. If
         * buftype is noncontiguous, we pack buf into xbuf, a contiguous buffer.
         */
        MPI_Offset bnelems=0;

        if (bufcount > INT_MAX) DEBUG_RETURN_ERROR(NC_EINTOVERFLOW)

        /* itype (primitive MPI data type) from buftype
         * isize is the size of itype in bytes
         * bnelems is the number of itype elements in one buftype
         */
        err = ncmpii_dtype_decode(buftype, &itype, &isize, &bnelems,
                                  NULL, &isContig);
        if (err != NC_NOERR) return err;

        /* size in bufcount * buftype must match with counts[] */
        if (bnelems * bufcount != nelems) DEBUG_RETURN_ERROR(NC_EIOMISMATCH)
    }

    /* nbytes is the amount of this varn request in bytes */
    nbytes = nelems * xsize;

    /* for nonblocking API, return now if request size is zero */
    if (nbytes == 0) return NC_NOERR;

#ifndef ENABLE_LARGE_REQ
    if (nbytes > INT_MAX) DEBUG_RETURN_ERROR(NC_EMAX_REQ)
#endif

    /* check if type conversion and Endianness byte swap is needed */
    need_convert = ncmpii_need_convert(ncp->format, varp->xtype, itype);
    need_swap    = NEED_BYTE_SWAP(varp->xtype, itype);

    if (fIsSet(reqMode, NC_REQ_WR)) {
        /* check if in-place byte swap can be enabled */
        int in_place_swap = 0;
        if (need_swap) {
            if (fIsSet(ncp->flags, NC_MODE_SWAP_ON))
                in_place_swap = 1;
            else if (! fIsSet(ncp->flags, NC_MODE_SWAP_OFF)) { /* auto mode */
                if (nbytes > NC_BYTE_SWAP_BUFFER_SIZE)
                    in_place_swap = 1;
            }
        }

        /* Because we are going to break the varn request into multiple vara
         * requests, we allocate a contiguous buffer, xbuf, if buftype is not
         * contiguous. So, we can do byte-swap and type-conversion on xbuf.
         */
        if (fIsSet(reqMode, NC_REQ_NBB)) {
            /* for bput call, check if the remaining buffer space is sufficient
             * to accommodate this varn request. If yes, allocate a space for
             * xbuf.
             */
            if (ncp->abuf->size_allocated - ncp->abuf->size_used < nbytes)
                DEBUG_RETURN_ERROR(NC_EINSUFFBUF)
            err = ncmpio_abuf_malloc(ncp, nbytes, &xbuf, &abuf_index);
            if (err != NC_NOERR) return err;
        }
        else if (!need_convert && in_place_swap && isContig) {
            /* reuse buf and break it into multiple vara requests */
            xbuf = buf;
            if (need_swap) need_swap_back_buf = 1;
        }
        else { /* must allocate a buffer to convert/swap/pack */
            xbuf = NCI_Malloc((size_t)nbytes);
            free_xbuf = 1;
            if (xbuf == NULL) DEBUG_RETURN_ERROR(NC_ENOMEM)
        }

        /* when necessary, pack buf to xbuf and perform byte-swap and
         * type-conversion on xbuf, which will later be broken into num
         * sub-buffers, each to be added to the nonblocking request queue.
         */
        err = ncmpio_pack_xbuf(ncp->format, varp, bufcount, buftype, isContig,
                               nelems, itype, MPI_DATATYPE_NULL, need_convert,
                               need_swap, nbytes, buf, xbuf);
        if (err != NC_NOERR && err != NC_ERANGE) {
            if (fIsSet(reqMode, NC_REQ_NBB))
                ncmpio_abuf_dealloc(ncp, abuf_index);
            else if (free_xbuf)
                NCI_Free(xbuf);
            return err;
        }

        /* allocate/expand the size of nonblocking write request queue */
        int add_reqs=0;
        if (IS_RECVAR(varp) && counts != NULL) {
            for (i=0; i<num; i++)
                add_reqs += (int)counts[i][0];
        }
        else
            add_reqs = num;

        int rem = ncp->numPutReqs % NC_REQUEST_CHUNK;
        if (rem) rem = NC_REQUEST_CHUNK - rem;

        if (ncp->put_list == NULL || add_reqs > rem) {
            size_t req_alloc, nChunks;
            req_alloc = ncp->numPutReqs + add_reqs;
            nChunks = req_alloc / NC_REQUEST_CHUNK;
            if (req_alloc % NC_REQUEST_CHUNK) nChunks++;
            req_alloc = nChunks * NC_REQUEST_CHUNK * sizeof(NC_req);
            ncp->put_list = (NC_req*) NCI_Realloc(ncp->put_list, req_alloc);
        }
    }
    else { /* read request */
        /* Type conversion and byte swap for read, if necessary, will be done
         * at the ncmpi_wait call */

        if (!need_convert && isContig) {
            /* reuse buf in later MPI file read */
            xbuf = buf;
        }
        else { /* must allocate a buffer for read/convert/swap/unpack */
            xbuf = NCI_Malloc((size_t)nbytes);
            if (xbuf == NULL) DEBUG_RETURN_ERROR(NC_ENOMEM)
            free_xbuf = 1;
        }

        /* allocate/expand the size of nonblocking read request queue */
        int add_reqs=0;
        if (IS_RECVAR(varp) && counts != NULL) {
            for (i=0; i<num; i++)
                add_reqs += (int)counts[i][0];
        }
        else
            add_reqs = num;

        int rem = ncp->numGetReqs % NC_REQUEST_CHUNK;
        if (rem) rem = NC_REQUEST_CHUNK - rem;

        if (ncp->get_list == NULL || add_reqs > rem) {
            size_t req_alloc, nChunks;
            req_alloc = ncp->numGetReqs + add_reqs;
            nChunks = req_alloc / NC_REQUEST_CHUNK;
            if (req_alloc % NC_REQUEST_CHUNK) nChunks++;
            req_alloc = nChunks * NC_REQUEST_CHUNK * sizeof(NC_req);
            ncp->get_list = (NC_req*) NCI_Realloc(ncp->get_list, req_alloc);
        }
    }

    /* break varn into multiple requests and buf/xbuf into num sub-buffers and
     * each is used in a new request object and added to the request queues.
     */
    memChunk = varp->ndims * SIZEOF_MPI_OFFSET;
    reqid = NC_REQ_NULL;
    xbufp = (char*)xbuf;
    for (i=0; i<num; i++) {
        MPI_Offset req_len=1; /* number of array elements in request i */
        if (counts != NULL) {
            for (j=0; j<varp->ndims; j++)
                req_len *= counts[i][j];
            if (req_len == 0) continue; /* ignore this 0-length request i */
        }

        if (fIsSet(reqMode, NC_REQ_WR))
            req = ncp->put_list + ncp->numPutReqs;
        else
            req = ncp->get_list + ncp->numGetReqs;

        req->flag        = 0;
        req->varp        = varp;
        req->itype       = itype;
        req->xbuf        = xbufp;
        xbufp += req_len * xsize;

        /* below matter only for the lead request */
        req->buf         = NULL;
        req->abuf_index  = -1;
        req->nelems      = 0;
        req->bufcount    = 0;
        req->buftype     = MPI_DATATYPE_NULL;
        req->imaptype    = MPI_DATATYPE_NULL;
        req->status      = NULL;

        /* varn APIs have no argument stride */
        fSet(req->flag, NC_REQ_STRIDE_NULL);

        if (reqid == NC_REQ_NULL) { /* lead request of the varn group */
            /* mark the first request as the lead request. Only lead requests
             * may free xbuf. For read, only the lead requests perform
             * byte-swap, type-conversion, imap unpack, and buftype unpacking
             * from xbuf to buf.
             */
            fSet(req->flag, NC_REQ_LEAD);
            req->nelems = nelems;
            req->buf = buf;
            if (free_xbuf) fSet(req->flag, NC_REQ_XBUF_TO_BE_FREED);

            /* Lead request allocates a single array to store num start/count
             * for all requests, including sub-requests if record variable.
             */
            req->start = (MPI_Offset*) NCI_Malloc(memChunk * 2 * max_nreqs);
            start_ptr = req->start;

            if (fIsSet(reqMode, NC_REQ_WR)) {
                /* when abuf_index >= 0 means called by bput_varn */
                req->abuf_index = abuf_index; /* to mark space in abuf free */

                /* whether user write buffer has been byte-swapped */
                if (need_swap_back_buf) fSet(req->flag, NC_REQ_BUF_BYTE_SWAP);

                /* new request ID is an even number (max of write ID + 2) */
                req->id = 0;
                if (ncp->numPutReqs > 0)
                    req->id = ncp->put_list[ncp->numPutReqs-1].id + 2;
                reqid = req->id;
            }
            else { /* read request */
                if (need_convert) fSet(req->flag, NC_REQ_BUF_TYPE_CONVERT);
                if (need_swap)    fSet(req->flag, NC_REQ_BUF_BYTE_SWAP);

                if (isContig)
                    fSet(req->flag, NC_REQ_BUF_TYPE_IS_CONTIG);
                else {
                    /* When read buftype is not contiguous, we duplicate
                     * buftype for later in the wait call to unpack xbuf
                     * using buftype to user buffer, buf.
                     */
                    MPI_Type_dup(buftype, &req->buftype);
                    req->bufcount = (int)bufcount;
                }

                /* new request ID is an odd number (max of read ID + 2) */
                req->id = 1;
                if (ncp->numGetReqs > 0)
                    req->id = ncp->get_list[ncp->numGetReqs-1].id + 2;
                reqid = req->id;
            }
        }
        else {
            /* Non-lead requests use the same reqid of the lead, so we end up
             * with one nonblocking request (only the lead request gets a new
             * request ID).
             */
            req->id = reqid;
        }

        /* copy starts[i] and counts[i] over to req */
        req->start = start_ptr;
        memcpy(start_ptr, starts[i], memChunk);
        start_ptr += varp->ndims;
        if (counts == NULL) {
            for (j=0; j<varp->ndims; j++)
                 start_ptr[j] = 1;
        }
        else
            memcpy(start_ptr, counts[i], memChunk);
        start_ptr += varp->ndims;

        if (IS_RECVAR(varp) && counts != NULL && counts[i][0] > 1) {
            /* If this is a record variable and the number of requested
             * records is more than 1, we split this request into multiple
             * (sub)requests, one for each record. The number of records is
             * only preserved in the lead request counts[i][0]. The rest
             * sub-requests counts[i][0] are set to 1.
             */

            /* add (counts[i][0]-1) number of (sub)requests to the queue */
            ncmpio_add_record_requests(req, NULL);
            start_ptr += (counts[i][0] - 1) * 2 * varp->ndims;

            if (fIsSet(reqMode, NC_REQ_WR)) ncp->numPutReqs += counts[i][0];
            else                            ncp->numGetReqs += counts[i][0];
        }
        else {
            if (fIsSet(reqMode, NC_REQ_WR)) ncp->numPutReqs++;
            else                            ncp->numGetReqs++;
        }
    }

    if (reqidp != NULL) *reqidp = reqid;

    return NC_NOERR;
}


include(`utils.m4')

dnl
define(`IsBput',    `ifelse(`$1',`bput', `1', `0')')dnl
define(`BufConst',  `ifelse(`$1',`get', , `const')')dnl
dnl
dnl VARN(iget/iput/bput)
dnl
define(`VARN',dnl
`dnl
/*----< ncmpio_$1_varn() >----------------------------------------------------*/
int
ncmpio_$1_varn(void               *ncdp,
               int                 varid,
               int                 num,
               MPI_Offset* const  *starts,
               MPI_Offset* const  *counts,
               BufConst(substr($1,1)) void  *buf,
               MPI_Offset          bufcount,
               MPI_Datatype        buftype,
               int                *reqid,
               int                 reqMode)
{
    NC *ncp=(NC*)ncdp;

    if (reqid != NULL) *reqid = NC_REQ_NULL;

    /* Note sanity check for ncdp and varid has been done in the dispatcher.
     * The same for zero-size request checking (return immediately)
     */

    if (fIsSet(reqMode, NC_REQ_ZERO)) return NC_NOERR;

    return igetput_varn(ncp, ncp->vars.value[varid], num, starts, counts,
                        (void*)buf, bufcount, buftype, reqid, reqMode);
}
')dnl
dnl

VARN(iput)
VARN(iget)
VARN(bput)

