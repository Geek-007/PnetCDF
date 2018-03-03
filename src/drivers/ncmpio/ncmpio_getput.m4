dnl Process this m4 file to produce 'C' language file.
dnl
dnl If you see this line, you can ignore the next one.
/* Do not edit this file. It is produced from the corresponding .m4 source */
dnl
/*
 *  Copyright (C) 2003, Northwestern University and Argonne National Laboratory
 *  See COPYRIGHT notice in top-level directory.
 */
/* $Id$ */

/*
 * This file implements the corresponding APIs defined in
 * src/dispatchers/var_getput.m4
 *
 * ncmpi_get_var<kind>()            : dispatcher->get_var()
 * ncmpi_put_var<kind>()            : dispatcher->put_var()
 * ncmpi_get_var<kind>_<type>()     : dispatcher->get_var()
 * ncmpi_put_var<kind>_<type>()     : dispatcher->put_var()
 * ncmpi_get_var<kind>_all()        : dispatcher->get_var()
 * ncmpi_put_var<kind>_all()        : dispatcher->put_var()
 * ncmpi_get_var<kind>_<type>_all() : dispatcher->get_var()
 * ncmpi_put_var<kind>_<type>_all() : dispatcher->put_var()
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
#ifdef ENABLE_SUBFILING
#include "ncmpio_subfile.h"
#endif

/* buffer layers:

   For write requests:
   buf   (user buffer of internal data type)
   lbuf  (contiguous buffer packed from buf based on buftype)
   cbuf  (contiguous buffer packed from lbuf based on imap)
   xbuf  (contiguous buffer in external data type, type-casted/byte-swapped
          from cbuf, ready to be used in MPI_File_write to write to file)

   For read requests:
   xbuf  (contiguous buffer to be used in MPI_File_read to read from file. Its
          contents are in external data type)
   cbuf  (contiguous buffer type-casted/byte-swapped from xbuf, its contents
          are in internal data type)
   lbuf  (contiguous buffer unpacked from cbuf based on imap)
   buf   (user buffer, unpacked from lbuf based on buftype)

   Note for varmi APIs:
        There maybe two layer of memory layout (remapping):
        one is specified by MPI derived datatype,
        the other is specified by imap[],
        it's encouraged to use only one option of them,
        though using both of them are supported.

   user buffer:                         |--------------------------|

   mpi derived datatype view:           |------|  |------|  |------|

   logic (contig) memory datastream:       |------|------|------|

   imap view:                              |--| |--|    |--| |--|

   contig I/O datastream (internal represent): |--|--|--|--|

   These two layers of memory layout will both be represented in MPI
   derived datatype, and if double layers of memory layout is used,
   we need to eliminate the upper one passed in MPI_Datatype parameter
   from the user, by packing it to logic contig memory datastream view.

   Implementation for put_varm:
     1. pack buf to lbuf based on buftype
     2. create imap_type based on imap
     3. pack lbuf to cbuf based on imap_type
     4. type convert and byte swap cbuf to xbuf
     5. write to file using xbuf
     6. byte swap user's buf, if it is swapped
     7. free up temp buffers (lbuf, cbuf, xbuf if != buf)

   Implementation for get_varm:
     1. allocate xbuf, if buf cannot be used to read from file
     2. read from file to xbuf
     3. type convert and byte swap xbuf to cbuf
     4. create imap_type based on imap
     5. unpack cbuf to lbuf based on imap_type
     6. unpack lbuf to buf based on buftype
     7. free up temp buffers (lbuf, cbuf, xbuf if != buf)
*/

/*----< put_varm() >------------------------------------------------------*/
static int
put_varm(NC               *ncp,
         NC_var           *varp,
         const MPI_Offset *start,
         const MPI_Offset *count,
         const MPI_Offset *stride,  /* can be NULL */
         const MPI_Offset *imap,    /* can be NULL */
         void             *buf,
         MPI_Offset        bufcount,  /* -1: from high-level API */
         MPI_Datatype      buftype,
         int               reqMode)   /* WR/RD/COLL/INDEP */
{
    void *xbuf=NULL;
    int mpireturn, err=NC_NOERR, status=NC_NOERR, buftype_is_contig;
    int el_size, need_convert, need_swap, in_place_swap, need_swap_back_buf=0;
    MPI_Offset nelems=0, nbytes=0, offset=0;
    MPI_Status mpistatus;
    MPI_Datatype itype, xtype, imaptype, filetype=MPI_BYTE;
    MPI_File fh;

    /* decode buftype to obtain the followings:
     * itype:    element data type (MPI primitive type) in buftype
     * bufcount: If it is -1, then this is called from a high-level API and in
     *           this case buftype will be an MPI primitive data type.
     *           If it is >=0, then this is called from a flexible API.
     * nelems:   number of itypes in user buffer, buf. It is also the number
     *           of array elements to be written to file.
     * nbytes:   number of bytes (in external data representation) to write to
     *           the file
     * el_size:  byte size of itype
     * buftype_is_contig: whether buftype is contiguous
     */
    err = ncmpii_buftype_decode(varp->ndims, varp->xtype, count, bufcount,
                                buftype, &itype, &el_size, &nelems,
                                &nbytes, &buftype_is_contig);
    if (err != NC_NOERR) goto err_check;

    /* because nelems will be used as the argument "count" in MPI-IO
     * write calls and the argument "count" is of type int */
    if (nelems > INT_MAX) {
        DEBUG_ASSIGN_ERROR(err, NC_EINTOVERFLOW)
        goto err_check;
    }
#ifndef ENABLE_LARGE_REQ
    /* Not all MPI-IO libraries support single requests larger than 2 GiB */
    if (nbytes > INT_MAX) {
        DEBUG_ASSIGN_ERROR(err, NC_EMAX_REQ)
        goto err_check;
    }
#endif

    if (nbytes == 0) /* this process has nothing to write */
        goto err_check;

    /* check if type conversion and Endianness byte swap is needed */
    need_convert = ncmpii_need_convert(ncp->format, varp->xtype, itype);
    need_swap    = NEED_BYTE_SWAP(varp->xtype, itype);

    if (fIsSet(ncp->flags, NC_MODE_SWAP_ON))
        in_place_swap = 1;
    else if (fIsSet(ncp->flags, NC_MODE_SWAP_OFF))
        in_place_swap = 0;
    else { /* mode is auto */
        if (nbytes <= NC_BYTE_SWAP_BUFFER_SIZE)
            in_place_swap = 0;
        else
            in_place_swap = 1;
    }

    /* check whether this is a true varm call, if yes, imaptype will be a
     * newly created MPI derived data type, otherwise MPI_DATATYPE_NULL
     */
    err = ncmpii_create_imaptype(varp->ndims, count, imap, itype, &imaptype);
    if (err != NC_NOERR) goto err_check;

    if (!buftype_is_contig || imaptype != MPI_DATATYPE_NULL || need_convert
        || (need_swap && in_place_swap == 0)) {
        xbuf = NCI_Malloc((size_t)nbytes);
        if (xbuf == NULL) {
            DEBUG_ASSIGN_ERROR(err, NC_ENOMEM)
            goto err_check;
        }
        need_swap_back_buf = 0;
    }
    else {
        /* when user buf is used as xbuf, we need to byte-swap buf back to its
         * original contents, after MPI_File_write */
        xbuf = buf;
        need_swap_back_buf = 1;
    }

    /* pack user buffer, buf, to xbuf, which will be used to write to file */
    err = ncmpio_pack_xbuf(ncp->format, varp, bufcount, buftype,
                           buftype_is_contig, nelems, itype, imaptype,
                           need_convert, need_swap, nbytes, buf, xbuf);
    if (err != NC_NOERR && err != NC_ERANGE) {
        if (xbuf != buf) NCI_Free(xbuf);
        xbuf = NULL;
        goto err_check;
    }

err_check:
    status = err;

    /* NC_ERANGE is not a fatal error, we proceed with write request */
    if ((err != NC_NOERR && err != NC_ERANGE) || nbytes == 0) {
        /* for independent API, this process returns now */
        if (fIsSet(reqMode, NC_REQ_INDEP)) return err;

        /* for collective API, this process needs to participate the
         * collective I/O operations, but with zero-length request
         */
        filetype = MPI_BYTE;
        nbytes   = 0;
    }
    else {
        /* Create the filetype for this request and calculate the beginning
         * file offset for this request. If this request is contiguous in file,
         * then set filetype == MPI_BYTE. Otherwise filetype will be an MPI
         * derived data type.
         */
        err = ncmpio_filetype_create_vars(ncp, varp, start, count, stride,
                                          reqMode, NULL, &offset, &filetype,
                                          NULL);
        if (err != NC_NOERR) {
            filetype = MPI_BYTE;
            nbytes   = 0;
            if (status == NC_NOERR) status = err;
        }
    }

    /* TODO: if record variables are too big (so big that we cannot store the
     * stride between records in an MPI_Aint, for example) then we will
     * have to process this one record at a time.
     */

    fh = (reqMode & NC_REQ_COLL) ? ncp->collective_fh : ncp->independent_fh;

    /* MPI_File_set_view is collective */
    err = ncmpio_file_set_view(ncp, fh, &offset, filetype);
    if (err != NC_NOERR) {
        nbytes = 0; /* skip this request */
        if (status == NC_NOERR) status = err;
    }
    if (filetype != MPI_BYTE) MPI_Type_free(&filetype);

#ifdef _USE_MPI_GET_COUNT
    /* explicitly initialize mpistatus object to 0, see comments below */
    memset(&mpistatus, 0, sizeof(MPI_Status));
#endif

    xtype = ncmpii_nc2mpitype(varp->xtype);
    /* xtype is the element data type (MPI primitive type) in xbuf to be
     * written to the variable defined in file. Note data stored in xbuf is in
     * the external data type, ready to be written to file.
     */
    if (fIsSet(reqMode, NC_REQ_COLL)) {
        TRACE_IO(MPI_File_write_at_all)(fh, offset, xbuf, (int)nelems,
                                        xtype, &mpistatus);
        if (mpireturn != MPI_SUCCESS) {
            err = ncmpii_error_mpi2nc(mpireturn, "MPI_File_write_at_all");
            /* return the first encountered error if there is any */
            if (status == NC_NOERR) {
                err = (err == NC_EFILE) ? NC_EWRITE : err;
                DEBUG_ASSIGN_ERROR(status, err)
            }
        }
    }
    else {  /* reqMode == NC_REQ_INDEP */
        TRACE_IO(MPI_File_write_at)(fh, offset, xbuf, (int)nelems,
                                    xtype, &mpistatus);
        if (mpireturn != MPI_SUCCESS) {
            err = ncmpii_error_mpi2nc(mpireturn, "MPI_File_write_at");
            /* return the first encountered error if there is any */
            if (status == NC_NOERR) {
                err = (err == NC_EFILE) ? NC_EWRITE : err;
                DEBUG_ASSIGN_ERROR(status, err)
            }
        }
    }
    if (mpireturn == MPI_SUCCESS) {
#ifdef _USE_MPI_GET_COUNT
        int put_size;
        MPI_Get_count(&mpistatus, MPI_BYTE, &put_size);
        ncp->put_size += put_size;
#else
        ncp->put_size += nbytes;
#endif
    }

    /* done with xbuf */
    if (xbuf != NULL && xbuf != buf) NCI_Free(xbuf);

    if (need_swap_back_buf) /* byte-swap back to buf's original contents */
        ncmpii_in_swapn(buf, nelems, varp->xsz);

    /* for record variable, update number of records */
    if (IS_RECVAR(varp)) {
        /* update header's number of records in memory */
        MPI_Offset new_numrecs = ncp->numrecs;

        /* calculate the max record ID written by this request */
        if (status == NC_NOERR || status == NC_ERANGE) {
            if (stride == NULL)
                new_numrecs = start[0] + count[0];
            else
                new_numrecs = start[0] + (count[0] - 1) * stride[0] + 1;

            /* note new_numrecs can be smaller than ncp->numrecs when this
             * write request writes existing records */
        }

        if (fIsSet(reqMode, NC_REQ_COLL)) {
            /* sync numrecs in memory and file. Note new_numrecs may be
             * different among processes. First, find the max numrecs among
             * all processes.
             */
            MPI_Offset max_numrecs;
            TRACE_COMM(MPI_Allreduce)(&new_numrecs, &max_numrecs, 1,
                                      MPI_OFFSET, MPI_MAX, ncp->comm);
            if (mpireturn != MPI_SUCCESS) {
                err = ncmpii_error_mpi2nc(mpireturn, "MPI_Allreduce");
                if (status == NC_NOERR) status = err;
            }
            /* In collective mode, ncp->numrecs is always sync-ed among
               processes */
            if (ncp->numrecs < max_numrecs) {
                err = ncmpio_write_numrecs(ncp, max_numrecs);
                if (status == NC_NOERR) status = err;
                ncp->numrecs = max_numrecs;
            }
        }
        else { /* NC_REQ_INDEP */
            /* For independent put, we delay the sync for numrecs until
             * the next collective call, such as end_indep(), sync(),
             * enddef(), or close(). This is because if we update numrecs
             * to file now, race condition can happen. Note numrecs in
             * memory may be inconsistent and obsolete till then.
             */
            if (ncp->numrecs < new_numrecs) {
                ncp->numrecs = new_numrecs;
                set_NC_ndirty(ncp);
            }
        }
    }

    if (NC_doFsync(ncp)) { /* NC_SHARE is set */
        TRACE_IO(MPI_File_sync)(fh);
        if (fIsSet(reqMode, NC_REQ_COLL))
            TRACE_COMM(MPI_Barrier)(ncp->comm);
    }

    return status;
}

/*----< get_varm() >------------------------------------------------------*/
static int
get_varm(NC               *ncp,
         NC_var           *varp,
         const MPI_Offset *start,
         const MPI_Offset *count,
         const MPI_Offset *stride,  /* can be NULL */
         const MPI_Offset *imap,    /* can be NULL */
         void             *buf,
         MPI_Offset        bufcount,  /* -1: from high-level API */
         MPI_Datatype      buftype,
         int               reqMode)   /* WR/RD/COLL/INDEP */
{
    void *xbuf=NULL;
    int mpireturn, err=NC_NOERR, status=NC_NOERR;
    int el_size, buftype_is_contig, need_swap=0, need_convert=0;
    MPI_Offset nelems=0, nbytes=0, offset=0;
    MPI_Status mpistatus;
    MPI_Datatype itype, xtype, filetype=MPI_BYTE, imaptype=MPI_DATATYPE_NULL;
    MPI_File fh;

    /* decode buftype to see if we can use buf to read from file.
     * itype:    element data type (MPI primitive type) in buftype
     * bufcount: If it is -1, then this is called from a high-level API and in
     *           this case buftype will be an MPI primitive data type.
     *           If it is >=0, then this is called from a flexible API.
     * nelems:   number of itypes in user buffer, buf. It is also the number
     *           of array elements to be read from file.
     * nbytes:   number of bytes (in external data representation) to
     *           read from the file
     * el_size:  size of itype
     * buftype_is_contig: whether buftype is contiguous
     */
    err = ncmpii_buftype_decode(varp->ndims, varp->xtype, count, bufcount,
                                buftype, &itype, &el_size, &nelems,
                                &nbytes, &buftype_is_contig);
    if (err != NC_NOERR) goto err_check;

    /* because nelems will be used as the argument "count" in MPI-IO
     * write calls and the argument "count" is of type int */
    if (nelems > INT_MAX) {
        DEBUG_ASSIGN_ERROR(err, NC_EINTOVERFLOW)
        goto err_check;
    }
#ifndef ENABLE_LARGE_REQ
    /* Not all MPI-IO libraries support single requests larger than 2 GiB */
    if (nbytes > INT_MAX) {
        DEBUG_ASSIGN_ERROR(err, NC_EMAX_REQ)
        goto err_check;
    }
#endif

    if (nbytes == 0) /* this process has nothing to read */
        goto err_check;

    /* check if type conversion and Endianness byte swap is needed */
    need_convert = ncmpii_need_convert(ncp->format, varp->xtype, itype);
    need_swap    = NEED_BYTE_SWAP(varp->xtype, itype);

    /* Check if this is a true varm call. If yes, construct a derived
     * datatype, imaptype.
     */
    err = ncmpii_create_imaptype(varp->ndims, count, imap, itype, &imaptype);
    if (err != NC_NOERR) goto err_check;

    /* If we want to use user buffer, buf, to read data from the file,
     * following 3 conditions must be true.
     * 1. buftype is a contiguous MPI datatype and
     * 2. imap is either NULL or indicates a contiguous memory access.
     * 3. xtype and itype matches (need_convert is false)
     * For condition 1, buftype is decoded in ncmpii_buftype_decode()
     * For condition 2, imap is checked in ncmpii_create_imaptype()
     */
    if (buftype_is_contig && imaptype == MPI_DATATYPE_NULL && !need_convert)
        xbuf = buf;
    else /* allocate xbuf for reading */
        xbuf = NCI_Malloc((size_t)nbytes);

    /* Note xbuf is the buffer to be used in MPI read calls, and hence its
     * contents are in the external type */

err_check:
    status = err;

    if (err != NC_NOERR || nbytes == 0) {
        /* for independent API, this process returns now */
        if (fIsSet(reqMode, NC_REQ_INDEP)) return err;

        /* for collective API, this process needs to participate the
         * collective I/O operations, but with zero-length request
         */
        filetype = MPI_BYTE;
        nbytes   = 0;
    }
    else {
        /* Create the filetype for this request and calculate the beginning
         * file offset for this request. If this request is contiguous in file,
         * then set filetype == MPI_BYTE. Otherwise filetype will be an MPI
         * derived data type.
         */
        err = ncmpio_filetype_create_vars(ncp, varp, start, count, stride,
                                          reqMode, NULL, &offset, &filetype,
                                          NULL);
        if (err != NC_NOERR) {
            filetype = MPI_BYTE;
            nbytes   = 0;
            if (status == NC_NOERR) status = err;
        }
    }

    /* TODO: if record variables are too big (so big that we cannot store the
     * stride between records in an MPI_Aint, for example) then we will
     * have to process this one record at a time.
     */

    fh = (reqMode & NC_REQ_COLL) ? ncp->collective_fh : ncp->independent_fh;

    /* MPI_File_set_view is collective */
    err = ncmpio_file_set_view(ncp, fh, &offset, filetype);
    if (err != NC_NOERR) {
        nbytes = 0; /* skip this request */
        if (status == NC_NOERR) status = err;
    }
    if (filetype != MPI_BYTE) MPI_Type_free(&filetype);

#ifdef _USE_MPI_GET_COUNT
    /* explicitly initialize mpistatus object to 0, see comments below */
    memset(&mpistatus, 0, sizeof(MPI_Status));
#endif

    xtype = ncmpii_nc2mpitype(varp->xtype);
    /* xtype is the element data type (MPI primitive type) in xbuf to be
     * read from the variable defined in file. Note xbuf will contain data read
     * from the file and hence is in the external data type.
     */
    if (fIsSet(reqMode, NC_REQ_COLL)) {
        TRACE_IO(MPI_File_read_at_all)(fh, offset, xbuf, (int)nelems,
                                       xtype, &mpistatus);
        if (mpireturn != MPI_SUCCESS) {
            err = ncmpii_error_mpi2nc(mpireturn, "MPI_File_read_at_all");
            /* return the first encountered error if there is any */
            if (status == NC_NOERR) {
                err = (err == NC_EFILE) ? NC_EREAD : err;
                DEBUG_ASSIGN_ERROR(status, err)
            }
        }
    }
    else {  /* reqMode == NC_REQ_INDEP */
        TRACE_IO(MPI_File_read_at)(fh, offset, xbuf, (int)nelems,
                                   xtype, &mpistatus);
        if (mpireturn != MPI_SUCCESS) {
            err = ncmpii_error_mpi2nc(mpireturn, "MPI_File_read_at");
            /* return the first encountered error if there is any */
            if (status == NC_NOERR) {
                err = (err == NC_EFILE) ? NC_EREAD : err;
                DEBUG_ASSIGN_ERROR(status, err)
            }
        }
    }
    if (mpireturn == MPI_SUCCESS) {
#ifdef _USE_MPI_GET_COUNT
        int get_size;
        MPI_Get_count(&mpistatus, MPI_BYTE, &get_size);
        ncp->get_size += get_size;
#else
        ncp->get_size += nbytes;
#endif
    }

    if (nbytes == 0) return status;

    /* unpack xbuf into user buffer, buf */
    err = ncmpio_unpack_xbuf(ncp->format, varp, bufcount, buftype,
                             buftype_is_contig, nelems, itype, imaptype,
                             need_convert, need_swap, buf, xbuf);
    if (status == NC_NOERR) status = err;

    if (xbuf != buf) NCI_Free(xbuf);

    return status;
}

include(`utils.m4')dnl
dnl
dnl GETPUT_API(get/put)
dnl
define(`GETPUT_API',dnl
`dnl
/*----< ncmpio_$1_var() >----------------------------------------------------*/
/* start  can be NULL only when api is NC_VAR
 * count  can be NULL only when api is NC_VAR or NC_VAR1
 * stride can be NULL only when api is NC_VAR, NC_VAR1, or NC_VARA
 * imap   can be NULL only when api is NC_VAR, NC_VAR1, NC_VARA, or NC_VARS
 * bufcount is >= 0 when called from a flexible API, is -1 when called from a
 *         high-level API and in this case buftype is an MPI primitive
 *         datatype.
 * buftype is an MPI primitive data type (corresponding to the internal data
 *         type of buf, e.g. short in ncmpi_put_short is mapped to MPI_SHORT)
 *         if called from a high-level APIs. When called from a flexible API
 *         it can be an MPI derived data type or MPI_DATATYPE_NULL. If it is
 *         MPI_DATATYPE_NULL, then it means the data type of buf in memory
 *         matches the variable external data type. In this case, bufcount is
 *         ignored.
 * reqMode indicates modes (NC_REQ_COLL/NC_REQ_INDEP/NC_REQ_WR etc.)
 */
int
ncmpio_$1_var(void             *ncdp,
              int               varid,
              const MPI_Offset *start,
              const MPI_Offset *count,
              const MPI_Offset *stride,
              const MPI_Offset *imap,
              ifelse(`$1',`put',`const') void *buf,
              MPI_Offset        bufcount,
              MPI_Datatype      buftype,
              int               reqMode)

{
    NC     *ncp=(NC*)ncdp;
    NC_var *varp=NULL;

    /* sanity check has been done at dispatchers */

    if (fIsSet(reqMode, NC_REQ_ZERO) && fIsSet(reqMode, NC_REQ_COLL))
        /* this collective API has a zero-length request */
        return ncmpio_getput_zero_req(ncp, reqMode);

    /* obtain NC_var object pointer, varp. Note sanity check for ncdp and
     * varid has been done in dispatchers */
    varp = ncp->vars.value[varid];

#ifdef ENABLE_SUBFILING
    /* call a separate routine if variable is stored in subfiles */
    if (varp->num_subfiles > 1) {
        if (imap != NULL) {
            fprintf(stderr, "varm APIs for subfiling is NOT implemented\n");
            DEBUG_RETURN_ERROR(NC_ENOTSUPPORT)
        }
        else
            return ncmpio_subfile_getput_vars(ncp, varp, start, count,
                                              stride, (void*)buf, bufcount,
                                              buftype, reqMode);
    }
#endif
    return $1_varm(ncp, varp, start, count, stride, imap, (void*)buf,
                   bufcount, buftype, reqMode);
}
')dnl
dnl

GETPUT_API(get)
GETPUT_API(put)
