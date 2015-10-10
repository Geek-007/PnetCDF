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

#if HAVE_CONFIG_H
# include "ncconfig.h"
#endif

#include <stdio.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <string.h>
#include <assert.h>

#include <mpi.h>

#include "nc.h"
#include "ncx.h"
#include "fbits.h"
#include "rnd.h"
#include "macro.h"
#include "utf8proc.h"

/*----< ncmpii_free_NC_attr() >-----------------------------------------------*/
/*
 * Free attr
 * Formerly
NC_free_attr()
 */
inline void
ncmpii_free_NC_attr(NC_attr *attrp)
{
    if (attrp == NULL) return;

    ncmpii_free_NC_string(attrp->name);

    NCI_Free(attrp);
}


/*----< ncmpix_len_NC_attrV() >----------------------------------------------*/
/*
 * How much space will 'nelems' of 'type' take in
 * external representation (as the values of an attribute)?
 */
inline static MPI_Offset
ncmpix_len_NC_attrV(nc_type    type,
                    MPI_Offset nelems)
{
    switch(type) {
        case NC_BYTE:
        case NC_CHAR:
        case NC_UBYTE:  return ncmpix_len_char(nelems);
        case NC_SHORT:  return ncmpix_len_short(nelems);
        case NC_USHORT: return ncmpix_len_ushort(nelems);
        case NC_INT:    return ncmpix_len_int(nelems);
        case NC_UINT:   return ncmpix_len_uint(nelems);
        case NC_FLOAT:  return ncmpix_len_float(nelems);
        case NC_DOUBLE: return ncmpix_len_double(nelems);
        case NC_INT64:  return ncmpix_len_int64(nelems);
        case NC_UINT64: return ncmpix_len_uint64(nelems);
        default: assert("ncmpix_len_NC_attr bad type" == 0);
    }
    return 0;
}


NC_attr *
ncmpii_new_x_NC_attr(NC_string  *strp,
                     nc_type     type,
                     MPI_Offset  nelems)
{
    NC_attr *attrp;
    const MPI_Offset xsz = ncmpix_len_NC_attrV(type, nelems);
    size_t sz = M_RNDUP(sizeof(NC_attr));

    assert(!(xsz == 0 && nelems != 0));

    sz += (size_t)xsz;

    attrp = (NC_attr *) NCI_Malloc(sz);
    if (attrp == NULL ) return NULL;

    attrp->xsz    = xsz;
    attrp->name   = strp;
    attrp->type   = type;
    attrp->nelems = nelems;

    if (xsz != 0)
        attrp->xvalue = (char *)attrp + M_RNDUP(sizeof(NC_attr));
    else
        attrp->xvalue = NULL;

    return(attrp);
}


/*----< ncmpii_new_NC_attr() >------------------------------------------------*/
/*
 * Formerly
NC_new_attr(name,type,count,value)
 */
static NC_attr *
ncmpii_new_NC_attr(const char *uname,  /* attribute name (NULL terminated) */
                   nc_type     type,
                   MPI_Offset  nelems)
{
    NC_string *strp;
    NC_attr *attrp;

    char *name = (char *)utf8proc_NFC((const unsigned char *)uname);
    if (name == NULL) return NULL;

    assert(name != NULL && *name != 0);

    strp = ncmpii_new_NC_string(strlen(name), name);
    free(name);
    if (strp == NULL) return NULL;

    attrp = ncmpii_new_x_NC_attr(strp, type, nelems);
    if (attrp == NULL) {
        ncmpii_free_NC_string(strp);
        return NULL;
    }

    return(attrp);
}


/*----< dup_NC_attr() >-------------------------------------------------------*/
NC_attr *
dup_NC_attr(const NC_attr *rattrp)
{
    NC_attr *attrp = ncmpii_new_NC_attr(rattrp->name->cp,
                                        rattrp->type,
                                        rattrp->nelems);
    if (attrp == NULL) return NULL;
    memcpy(attrp->xvalue, rattrp->xvalue, (size_t)rattrp->xsz);
    return attrp;
}

/* attrarray */

/*----< ncmpii_free_NC_attrarray() >------------------------------------------*/
/*
 * Free NC_attrarray values.
 * formerly
NC_free_array()
 */
void
ncmpii_free_NC_attrarray(NC_attrarray *ncap)
{
    int i;

    assert(ncap != NULL);

    if (ncap->nalloc == 0) return;

    assert(ncap->value != NULL);

    for (i=0; i<ncap->ndefined; i++)
        ncmpii_free_NC_attr(ncap->value[i]);

    NCI_Free(ncap->value);
    ncap->value    = NULL;
    ncap->nalloc   = 0;
    ncap->ndefined = 0;
}

/*----< ncmpii_dup_NC_attrarray() >-------------------------------------------*/
int
ncmpii_dup_NC_attrarray(NC_attrarray *ncap, const NC_attrarray *ref)
{
    int i, status=NC_NOERR;

    assert(ref != NULL);
    assert(ncap != NULL);

    if (ref->nalloc == 0) {
        ncap->nalloc   = 0;
        ncap->ndefined = 0;
        ncap->value    = NULL;
        return NC_NOERR;
    }

    if (ref->nalloc > 0) {
        ncap->value = (NC_attr **) NCI_Calloc((size_t)ref->nalloc, sizeof(NC_attr*));
        if (ncap->value == NULL) return NC_ENOMEM;
        ncap->nalloc = ref->nalloc;
    }

    ncap->ndefined = 0;
    for (i=0; i<ref->ndefined; i++) {
        ncap->value[i] = dup_NC_attr(ref->value[i]);
        if (ncap->value[i] == NULL) {
            status = NC_ENOMEM;
            break;
        }
    }

    if (status != NC_NOERR) {
        ncmpii_free_NC_attrarray(ncap);
        return status;
    }

    ncap->ndefined = ref->ndefined;

    return NC_NOERR;
}


/*
 * Add a new handle on the end of an array of handles
 * Formerly
NC_incr_array(array, tail)
 */
int
incr_NC_attrarray(NC_attrarray *ncap, NC_attr *newelemp)
{
	NC_attr **vp;

	assert(ncap != NULL);

	if(ncap->nalloc == 0)
	{
		assert(ncap->ndefined == 0);
		vp = (NC_attr **) NCI_Malloc(sizeof(NC_attr*) * NC_ARRAY_GROWBY);
		if(vp == NULL)
			return NC_ENOMEM;

		ncap->value = vp;
		ncap->nalloc = NC_ARRAY_GROWBY;
	}
	else if(ncap->ndefined +1 > ncap->nalloc)
	{
		vp = (NC_attr **) NCI_Realloc(ncap->value,
			(size_t)(ncap->nalloc + NC_ARRAY_GROWBY) * sizeof(NC_attr*));
		if(vp == NULL)
			return NC_ENOMEM;

		ncap->value = vp;
		ncap->nalloc += NC_ARRAY_GROWBY;
	}

	if(newelemp != NULL)
	{
		ncap->value[ncap->ndefined] = newelemp;
		ncap->ndefined++;
	}
	return NC_NOERR;
}


static NC_attr *
elem_NC_attrarray(const NC_attrarray *ncap, MPI_Offset elem)
{
	assert(ncap != NULL);
	if((elem < 0) || ncap->ndefined == 0 || elem >= ncap->ndefined)
		return NULL;

	assert(ncap->value != NULL);

	return ncap->value[elem];
}

/* End attrarray per se */

/*----< NC_attrarray0() >----------------------------------------------------*/
/*
 * Given ncp and varid, return ptr to array of attributes
 * else NULL on error. This is equivalent to validate varid.
 */
static NC_attrarray *
NC_attrarray0(NC  *ncp,
              int  varid)
{
    if (varid == NC_GLOBAL) /* Global attribute, attach to cdf */
        return &ncp->attrs;

    if (varid >= 0 && varid < ncp->vars.ndefined)
        return &ncp->vars.value[varid]->attrs;

    return NULL;
}


/*----< ncmpii_NC_findattr() >------------------------------------------------*/
/*
 * Step thru NC_ATTRIBUTE array, seeking match on name.
 *  return match or -1 if Not Found.
 */
int
ncmpii_NC_findattr(const NC_attrarray *ncap,
                   const char         *uname)
{
    int i;
    size_t nchars;
    char *name;

    assert(ncap != NULL);

    if (ncap->ndefined == 0) return -1; /* none created yet */

    name = (char *)utf8proc_NFC((const unsigned char *)uname);
    nchars = strlen(name);

    for (i=0; i<ncap->ndefined; i++) {
        if (ncap->value[i]->name->nchars == nchars &&
            strncmp(ncap->value[i]->name->cp, name, nchars) == 0) {
            free(name);
            return i;
        }
    }
    free(name);

    return -1;
}


/*
 * Look up by ncid, varid and name, return NULL if not found
 */
static int
NC_lookupattr(int ncid,
    int varid,
    const char *name, /* attribute name */
    NC_attr **attrpp) /* modified on return */
{
    int indx, status;
    NC *ncp;
    NC_attrarray *ncap;

    status = ncmpii_NC_check_id(ncid, &ncp);
    if(status != NC_NOERR)
        return status;

    ncap = NC_attrarray0(ncp, varid);
    if(ncap == NULL)
        return NC_ENOTVAR;

    indx = ncmpii_NC_findattr(ncap, name);
    if(indx == -1)
        return NC_ENOTATT;

    if(attrpp != NULL)
        *attrpp = ncap->value[indx];

    return NC_NOERR;
}

/* Public */

/*----< ncmpi_inq_attname() >------------------------------------------------*/
int
ncmpi_inq_attname(int   ncid,
                  int   varid,
                  int   attid,
                  char *name)

{
    int status;
    NC *ncp;
    NC_attrarray *ncap;
    NC_attr *attrp;

    status = ncmpii_NC_check_id(ncid, &ncp);
    if (status != NC_NOERR) return status;

    ncap = NC_attrarray0(ncp, varid);
    if (ncap == NULL) return NC_ENOTVAR;

    attrp = elem_NC_attrarray(ncap, attid);
    if (attrp == NULL) return NC_ENOTATT;

    /* in PnetCDF, name->cp is always NULL character terminated */
    assert(name != NULL);
    strcpy(name, attrp->name->cp);

    return NC_NOERR;
}


/*----< ncmpi_inq_attid() >--------------------------------------------------*/
int
ncmpi_inq_attid(int         ncid,
                int         varid,
                const char *name,
                int        *attidp)
{
    int indx, status;
    NC *ncp;
    NC_attrarray *ncap;

    status = ncmpii_NC_check_id(ncid, &ncp);
    if (status != NC_NOERR) return status;

    ncap = NC_attrarray0(ncp, varid);
    if (ncap == NULL) return NC_ENOTVAR;

    indx = ncmpii_NC_findattr(ncap, name);
    if (indx == -1) return NC_ENOTATT;

    if (attidp != NULL)
        *attidp = indx;

    return NC_NOERR;
}

/*----< ncmpi_inq_att() >----------------------------------------------------*/
int
ncmpi_inq_att(int         ncid,
              int         varid,
              const char *name, /* input, attribute name */
              nc_type    *datatypep,
              MPI_Offset *lenp)
{
    int status;
    NC_attr *attrp;

    status = NC_lookupattr(ncid, varid, name, &attrp);
    if (status != NC_NOERR) return status;

    if (datatypep != NULL)
        *datatypep = attrp->type;

    if (lenp != NULL)
        *lenp = attrp->nelems;

    return NC_NOERR;
}

/*----< ncmpi_inq_atttype() >------------------------------------------------*/
int
ncmpi_inq_atttype(int         ncid,
                  int         varid,
                  const char *name,
                  nc_type    *datatypep)
{
    return ncmpi_inq_att(ncid, varid, name, datatypep, NULL);
}

/*----< ncmpi_inq_attlen() >-------------------------------------------------*/
int
ncmpi_inq_attlen(int         ncid,
                 int         varid,
                 const char *name,
                 MPI_Offset *lenp)
{
    return ncmpi_inq_att(ncid, varid, name, NULL, lenp);
}


/*----< ncmpi_rename_att() >--------------------------------------------------*/
/* This API is collective if called in data mode */
int
ncmpi_rename_att(int         ncid,
                 int         varid,
                 const char *name,
                 const char *newname)
{
    int indx, file_ver, status, err, mpireturn;
    NC *ncp;
    NC_attrarray *ncap;
    NC_attr *attrp;

    /* sortof inline clone of NC_lookupattr() */
    status = ncmpii_NC_check_id(ncid, &ncp);
    if (status != NC_NOERR) return status;

    if (NC_readonly(ncp)) return NC_EPERM;

    ncap = NC_attrarray0(ncp, varid);
    if (ncap == NULL) return NC_ENOTVAR;

    file_ver = 1;
    if (fIsSet(ncp->flags, NC_64BIT_OFFSET))
        file_ver = 2;
    else if (fIsSet(ncp->flags, NC_64BIT_DATA))
        file_ver = 5;

    status = ncmpii_NC_check_name(newname, file_ver);
    if (status != NC_NOERR) return status;

    indx = ncmpii_NC_findattr(ncap, name);
    if (indx < 0) return NC_ENOTATT;

    attrp = ncap->value[indx];
    /* end inline clone NC_lookupattr() */

    if (ncmpii_NC_findattr(ncap, newname) >= 0)
        /* name in use */
        return NC_ENAMEINUSE;

    if (NC_indef(ncp)) {
        NC_string *newStr = ncmpii_new_NC_string(strlen(newname), newname);
        if (newStr == NULL) return NC_ENOMEM;

        ncmpii_free_NC_string(attrp->name);
        attrp->name = newStr;
        return NC_NOERR;
    }
    /* else, not in define mode.
     * If called in data mode (collective or independent), this function must
     * be called collectively, i.e. all processes must participate
     */

    if (ncp->safe_mode) {
        int nchars = (int) strlen(newname);
        TRACE_COMM(MPI_Bcast)(&nchars, 1, MPI_INT, 0, ncp->nciop->comm);
        if (mpireturn != MPI_SUCCESS)
            return ncmpii_handle_error(mpireturn, "MPI_Bcast"); 

        if (nchars != strlen(newname)) {
            /* newname's length is inconsistent with root's */
            printf("Warning: attribute name(%s) used in %s() is inconsistent\n",
                   newname, __func__);
            if (status == NC_NOERR) status = NC_EMULTIDEFINE_ATTR_NAME;
        }
    }

    /* ncmpii_set_NC_string() will check for strlen(newname) > nchars error */
    err = ncmpii_set_NC_string(attrp->name, newname);
    if (status == NC_NOERR) status = err;

    /* PnetCDF expects all processes use the same name, However, when names
     * are not the same, only root's value is significant. Broadcast the
     * new name at root to overwrite new names at other processes.
     * (This API is collective if called in data mode)
     */
    TRACE_COMM(MPI_Bcast)(attrp->name->cp, (int)attrp->name->nchars, MPI_CHAR, 0,
                          ncp->nciop->comm);

    /* Let root write the entire header to the file. Note that we cannot just
     * update the variable name in its space occupied in the file header,
     * because if the file space occupied by the name shrinks, all the metadata
     * following it must be moved ahead.
     */
    err = ncmpii_write_header(ncp);
    if (status == NC_NOERR) status = err;

    return status;
}


/*----< ncmpi_copy_att() >----------------------------------------------------*/
/* This API is collective if called in data mode */
int
ncmpi_copy_att(int         ncid_in,
               int         varid_in,
               const char *name,
               int         ncid_out,
               int         varid_out)
{
    int indx, status, mpireturn;
    NC *ncp;
    NC_attrarray *ncap;
    NC_attr *iattrp, *attrp, *old=NULL;

    status = NC_lookupattr(ncid_in, varid_in, name, &iattrp);
    if (status != NC_NOERR) return status;

    status = ncmpii_NC_check_id(ncid_out, &ncp);
    if (status != NC_NOERR) return status;

    if (NC_readonly(ncp)) return NC_EPERM;

    ncap = NC_attrarray0(ncp, varid_out);
    if (ncap == NULL) return NC_ENOTVAR;

    indx = ncmpii_NC_findattr(ncap, name);
    if (indx >= 0) { /* name in use */
        if (!NC_indef(ncp)) {
            /* if called in data mode (collective or independent), this
             * function must be called collectively, i.e. all processes must
             * participate
             */

            attrp = ncap->value[indx]; /* convenience */

            if (iattrp->xsz > attrp->xsz) return NC_ENOTINDEFINE;
            /* else, we can reuse existing without redef */

            if (iattrp->xsz != (int)iattrp->xsz) return NC_EINTOVERFLOW;

            attrp->xsz = iattrp->xsz;
            attrp->type = iattrp->type;
            attrp->nelems = iattrp->nelems;

            memcpy(attrp->xvalue, iattrp->xvalue, (size_t)iattrp->xsz);

            /* PnetCDF expects all processes use the same name, However, when
             * new attributes are not the same, only root's value is
             * significant. Broadcast the new attribute at root to overwrite
             * new names at other processes.
             */
            TRACE_COMM(MPI_Bcast)((void*)attrp->xvalue, (int)attrp->xsz,
                                  MPI_CHAR, 0, ncp->nciop->comm);
            if (mpireturn != MPI_SUCCESS)
                return ncmpii_handle_error(mpireturn, "MPI_Bcast"); 

            /* Let root write the entire header to the file. Note that we
             * cannot just update the variable name in its space occupied in
             * the file header, because if the file space occupied by the name
             * shrinks, all the metadata following it must be moved ahead.
             */
            return ncmpii_write_header(ncp);
        }
        /* else, redefine using existing array slot */
        old = ncap->value[indx];
    }
    else {
        if (!NC_indef(ncp)) /* add new attribute is not allowed in data mode */
            return NC_ENOTINDEFINE;

        if (ncap->ndefined >= NC_MAX_ATTRS)
            return NC_EMAXATTS;
    }

    attrp = ncmpii_new_NC_attr(name, iattrp->type, iattrp->nelems);
    if (attrp == NULL) return NC_ENOMEM;

    memcpy(attrp->xvalue, iattrp->xvalue, (size_t)iattrp->xsz);

    if (indx >= 0) {
        assert(old != NULL);
        ncap->value[indx] = attrp;
        ncmpii_free_NC_attr(old);
    }
    else {
        status = incr_NC_attrarray(ncap, attrp);
        if (status != NC_NOERR) {
            ncmpii_free_NC_attr(attrp);
            return status;
        }
    }
    return NC_NOERR;
}

/*----< ncmpi_del_att() >---------------------------------------------------*/
int
ncmpi_del_att(int         ncid,
              int         varid,
              const char *name)
{
    int status, attrid;
    NC *ncp;
    NC_attrarray *ncap;

    status = ncmpii_NC_check_id(ncid, &ncp);
    if (status != NC_NOERR) return status;

    if (!NC_indef(ncp)) return NC_ENOTINDEFINE;

    ncap = NC_attrarray0(ncp, varid);
    if (ncap == NULL) return NC_ENOTVAR;

    attrid = ncmpii_NC_findattr(ncap, name);
    if (attrid == -1) return NC_ENOTATT;

    /* deleting attribute _FillValue means disabling fill mode */
    if (!strcmp(name, _FillValue)) {
        NC_var *varp;
        status = ncmpii_NC_lookupvar(ncp, varid, &varp);
        if (status != NC_NOERR) return status;
        varp->no_fill = 1;
    }

    ncmpii_free_NC_attr(ncap->value[attrid]);

    /* shuffle down */
    for (; attrid < ncap->ndefined; attrid++)
        ncap->value[attrid] = ncap->value[attrid+1];

    /* decrement count */
    ncap->ndefined--;

    return NC_NOERR;
}

static nc_type longtype = (SIZEOF_LONG == SIZEOF_INT ? NC_INT : NC_INT64);

/* ncmpi_pad_xxx APIs are only applicable for filetypes of size smaller
 * than 4 bytes
 */
dnl
dnl PAD_GETN_FILETYPE(filetype)
dnl
define(`PAD_GETN_FILETYPE',dnl
`dnl
/*----< ncmpix_pad_getn_$1() >-----------------------------------------------*/
inline static int
ncmpix_pad_getn_$1(const void **xpp,
                   MPI_Offset   nelems,
                   void        *tp,
                   nc_type      buftype)
{
    switch(buftype) {
        case NC_CHAR:
        case NC_BYTE:
            return ncmpix_pad_getn_$1_schar (xpp, nelems, (schar*)tp);
        case NC_UBYTE:
            return ncmpix_pad_getn_$1_uchar (xpp, nelems, (uchar*)tp);
        case NC_SHORT:
            return ncmpix_pad_getn_$1_short (xpp, nelems, (short*)tp);
        case NC_USHORT:
            return ncmpix_pad_getn_$1_ushort(xpp, nelems, (ushort*)tp);
        case NC_INT:
            return ncmpix_pad_getn_$1_int   (xpp, nelems, (int*)tp);
        case NC_UINT:
            return ncmpix_pad_getn_$1_uint  (xpp, nelems, (uint*)tp);
        case NC_FLOAT:
            return ncmpix_pad_getn_$1_float (xpp, nelems, (float*)tp);
        case NC_DOUBLE:
            return ncmpix_pad_getn_$1_double(xpp, nelems, (double*)tp);
        case NC_INT64:
            return ncmpix_pad_getn_$1_longlong (xpp, nelems, (longlong*)tp);
        case NC_UINT64:
            return ncmpix_pad_getn_$1_ulonglong(xpp, nelems, (ulonglong*)tp);
        default:
            assert("ncmpix_pad_getn_$1 invalid buffer type" == 0);
            return NC_EBADTYPE;
    }
}
')dnl

PAD_GETN_FILETYPE(schar)
PAD_GETN_FILETYPE(uchar)
PAD_GETN_FILETYPE(short)
PAD_GETN_FILETYPE(ushort)

dnl
dnl GETN_FILETYPE(filetype)
dnl
define(`GETN_FILETYPE',dnl
`dnl
/*----< ncmpix_getn_$1() >---------------------------------------------------*/
inline static int
ncmpix_getn_$1(const void **xpp,
               MPI_Offset   nelems,
               void        *tp,
               nc_type      buftype)
{
    switch(buftype) {
        case NC_CHAR:
        case NC_BYTE:
            return ncmpix_getn_$1_schar (xpp, nelems, (schar*)tp);
        case NC_UBYTE:
            return ncmpix_getn_$1_uchar (xpp, nelems, (uchar*)tp);
        case NC_SHORT:
            return ncmpix_getn_$1_short (xpp, nelems, (short*)tp);
        case NC_USHORT:
            return ncmpix_getn_$1_ushort(xpp, nelems, (ushort*)tp);
        case NC_INT:
            return ncmpix_getn_$1_int   (xpp, nelems, (int*)tp);
        case NC_UINT:
            return ncmpix_getn_$1_uint  (xpp, nelems, (uint*)tp);
        case NC_FLOAT:
            return ncmpix_getn_$1_float (xpp, nelems, (float*)tp);
        case NC_DOUBLE:
            return ncmpix_getn_$1_double(xpp, nelems, (double*)tp);
        case NC_INT64:
            return ncmpix_getn_$1_longlong (xpp, nelems, (longlong*)tp);
        case NC_UINT64:
            return ncmpix_getn_$1_ulonglong(xpp, nelems, (ulonglong*)tp);
        default:
            assert("ncmpix_pad_getn_$1 invalid buffer type" == 0);
            return NC_EBADTYPE;
    }
}
')dnl

GETN_FILETYPE(int)
GETN_FILETYPE(uint)
GETN_FILETYPE(float)
GETN_FILETYPE(double)
GETN_FILETYPE(int64)
GETN_FILETYPE(uint64)

/*----< ncmpix_pad_getn() >--------------------------------------------------*/
/* padding only applicable to file types of size smaller than 4 bytes */
inline static int
ncmpix_pad_getn(const void **xpp,
                MPI_Offset   nelems,
                void        *tp,
                nc_type      filetype,
                nc_type      buftype)
{
    /* get n elements from (filetype*)*xpp to (buftype*)tp */
    /* Checking for character-number conversion should have already been done */

    switch(filetype) {
        case NC_CHAR:
        case NC_BYTE:
            return ncmpix_pad_getn_schar (xpp, nelems, tp, buftype);
        case NC_UBYTE:
            return ncmpix_pad_getn_uchar (xpp, nelems, tp, buftype);
        case NC_SHORT:
            return ncmpix_pad_getn_short (xpp, nelems, tp, buftype);
        case NC_USHORT:
            return ncmpix_pad_getn_ushort(xpp, nelems, tp, buftype);
        case NC_INT:
            return ncmpix_getn_int       (xpp, nelems, tp, buftype);
        case NC_UINT:
            return ncmpix_getn_uint      (xpp, nelems, tp, buftype);
        case NC_FLOAT:
            return ncmpix_getn_float     (xpp, nelems, tp, buftype);
        case NC_DOUBLE:
            return ncmpix_getn_double    (xpp, nelems, tp, buftype);
        case NC_INT64:
            return ncmpix_getn_int64     (xpp, nelems, tp, buftype);
        case NC_UINT64:
            return ncmpix_getn_uint64    (xpp, nelems, tp, buftype);
        default:
            assert("ncmpix_pad_getn invalid filetype" == 0);
            return NC_EBADTYPE;
    }
}

/*----< ncmpii_get_att() >---------------------------------------------------*/
static int
ncmpii_get_att(int         ncid,
               int         varid,
               const char *name,
               void       *tp,       /* I/O buffer */
               nc_type     buftype)  /* I/O buffer data type */
{
    int status;
    NC_attr *attrp;

    status = NC_lookupattr(ncid, varid, name, &attrp);
    if (status != NC_NOERR) return status;

    if (attrp->nelems == 0) return NC_NOERR;

    /* No character conversions are allowed. */
    if (attrp->type != buftype &&
        (attrp->type == NC_CHAR || buftype == NC_CHAR))
        return NC_ECHAR;

    const void *xp = attrp->xvalue;
    return ncmpix_pad_getn(&xp, attrp->nelems, tp, attrp->type, buftype);
}

/*----< ncmpi_get_att() >-----------------------------------------------------*/
int
ncmpi_get_att(int         ncid,
              int         varid,
              const char *name,
              void       *value)
{
    int status;
    nc_type atttype;

    status = ncmpi_inq_atttype(ncid, varid, name, &atttype);
    if (status != NC_NOERR) return status;

    return ncmpii_get_att(ncid, varid, name, value, atttype);
}

dnl
dnl GET_ATT_TYPE(fntype, ext_buftype, nc_buftype)
dnl
define(`GET_ATT_TYPE',dnl
`dnl
/*----< ncmpi_get_att_$1() >-------------------------------------------------*/
int
ncmpi_get_att_$1(int ncid, int varid, const char  *name, $2 *value)
{
    return ncmpii_get_att(ncid, varid, name, value, $3);
}
')dnl

GET_ATT_TYPE(text,      char,               NC_CHAR)
GET_ATT_TYPE(schar,     signed char,        NC_BYTE)
GET_ATT_TYPE(uchar,     unsigned char,      NC_UBYTE)
GET_ATT_TYPE(ubyte,     unsigned char,      NC_UBYTE)
GET_ATT_TYPE(short,     short,              NC_SHORT)
GET_ATT_TYPE(ushort,    unsigned short,     NC_USHORT)
GET_ATT_TYPE(int,       int,                NC_INT)
GET_ATT_TYPE(uint,      unsigned int,       NC_UINT)
GET_ATT_TYPE(long,      long,               longtype)
GET_ATT_TYPE(float,     float,              NC_FLOAT)
GET_ATT_TYPE(double,    double,             NC_DOUBLE)
GET_ATT_TYPE(longlong,  long long,          NC_INT64)
GET_ATT_TYPE(ulonglong, unsigned long long, NC_UINT64)

dnl
dnl PAD_PUTN_FILETYPE(ftype)
dnl
define(`PAD_PUTN_FILETYPE',dnl
`dnl
/*----< ncmpix_pad_putn_$1() >-----------------------------------------------*/
inline static int
ncmpix_pad_putn_$1(void       **xpp,
                   MPI_Offset   nelems,
                   const void  *tp,
                   nc_type      btype)
{
    switch(btype) {
        case NC_CHAR:
        case NC_BYTE:
            return ncmpix_pad_putn_$1_schar (xpp, nelems, (schar*)tp);
        case NC_UBYTE:
            return ncmpix_pad_putn_$1_uchar (xpp, nelems, (uchar*)tp);
        case NC_SHORT:
            return ncmpix_pad_putn_$1_short (xpp, nelems, (short*)tp);
        case NC_USHORT:
            return ncmpix_pad_putn_$1_ushort(xpp, nelems, (ushort*)tp);
        case NC_INT:
            return ncmpix_pad_putn_$1_int   (xpp, nelems, (int*)tp);
        case NC_UINT:
            return ncmpix_pad_putn_$1_uint  (xpp, nelems, (uint*)tp);
        case NC_FLOAT:
            return ncmpix_pad_putn_$1_float (xpp, nelems, (float*)tp);
        case NC_DOUBLE:
            return ncmpix_pad_putn_$1_double(xpp, nelems, (double*)tp);
        case NC_INT64:
            return ncmpix_pad_putn_$1_longlong (xpp, nelems, (longlong*)tp);
        case NC_UINT64:
            return ncmpix_pad_putn_$1_ulonglong(xpp, nelems, (ulonglong*)tp);
        default:
            assert("ncmpix_pad_putn_$1 invalid type" == 0);
            return NC_EBADTYPE;
    }
}
')dnl

PAD_PUTN_FILETYPE(schar)
PAD_PUTN_FILETYPE(uchar)
PAD_PUTN_FILETYPE(short)
PAD_PUTN_FILETYPE(ushort)

dnl
dnl PUTN_FILETYPE(ftype)
dnl
define(`PUTN_FILETYPE',dnl
`dnl
/*----< ncmpix_putn_$1() >---------------------------------------------------*/
inline static int
ncmpix_putn_$1(void       **xpp,
               MPI_Offset   nelems,
               const void  *tp,
               nc_type      btype)
{
    switch(btype) {
        case NC_CHAR:
        case NC_BYTE:
            return ncmpix_putn_$1_schar (xpp, nelems, (schar*)tp);
        case NC_UBYTE:
            return ncmpix_putn_$1_uchar (xpp, nelems, (uchar*)tp);
        case NC_SHORT:
            return ncmpix_putn_$1_short (xpp, nelems, (short*)tp);
        case NC_USHORT:
            return ncmpix_putn_$1_ushort(xpp, nelems, (ushort*)tp);
        case NC_INT:
            return ncmpix_putn_$1_int   (xpp, nelems, (int*)tp);
        case NC_UINT:
            return ncmpix_putn_$1_uint  (xpp, nelems, (uint*)tp);
        case NC_FLOAT:
            return ncmpix_putn_$1_float (xpp, nelems, (float*)tp);
        case NC_DOUBLE:
            return ncmpix_putn_$1_double(xpp, nelems, (double*)tp);
        case NC_INT64:
            return ncmpix_putn_$1_longlong (xpp, nelems, (longlong*)tp);
        case NC_UINT64:
            return ncmpix_putn_$1_ulonglong(xpp, nelems, (ulonglong*)tp);
        default:
            assert("ncmpix_putn_$1 invalid type" == 0);
            return NC_EBADTYPE;
    }
}
')dnl

PUTN_FILETYPE(int)
PUTN_FILETYPE(uint)
PUTN_FILETYPE(float)
PUTN_FILETYPE(double)
PUTN_FILETYPE(int64)
PUTN_FILETYPE(uint64)

/*----< ncmpix_pad_putn() >--------------------------------------------------*/
/* padding only applicable to file types of size smaller than 4 bytes */
inline static int
ncmpix_pad_putn(void       **xpp,
                MPI_Offset   nelems,
                const void  *tp,
                nc_type      filetype,
                nc_type      buftype)
{
    /* put n elements from (buftype*)tp to (filetype*)*xpp */
    /* Checking for character-number conversion should have been done */

    switch(filetype) {
        case NC_CHAR:
        case NC_BYTE:
            return ncmpix_pad_putn_schar (xpp, nelems, tp, buftype);
        case NC_UBYTE:
            return ncmpix_pad_putn_uchar (xpp, nelems, tp, buftype);
        case NC_SHORT:
            return ncmpix_pad_putn_short (xpp, nelems, tp, buftype);
        case NC_USHORT:
            return ncmpix_pad_putn_ushort(xpp, nelems, tp, buftype);
        case NC_INT:
            return ncmpix_putn_int       (xpp, nelems, tp, buftype);
        case NC_UINT:
            return ncmpix_putn_uint      (xpp, nelems, tp, buftype);
        case NC_FLOAT:
            return ncmpix_putn_float     (xpp, nelems, tp, buftype);
        case NC_DOUBLE:
            return ncmpix_putn_double    (xpp, nelems, tp, buftype);
        case NC_INT64:
            return ncmpix_putn_int64     (xpp, nelems, tp, buftype);
        case NC_UINT64:
            return ncmpix_putn_uint64    (xpp, nelems, tp, buftype);
        default:
            assert("ncmpix_pad_putn invalid filetype" == 0);
            return NC_EBADTYPE;
    }
}

/*----< ncmpii_put_att() >---------------------------------------------------*/
/* Note from netCDF user guide:
 * Attributes are always single values or one-dimensional arrays. This works
 * out well for a string, which is a one-dimensional array of ASCII characters
 *
 * This PnetCDF API is collective if called in data mode.
 */
static int
ncmpii_put_att(int         ncid,
               int         varid,
               const char *name,     /* attribute name */
               nc_type     filetype, /* type defined in file header */
               MPI_Offset  nelems,   /* number of elements of type buftype */
               const void *buf,      /* I/O buffer */
               nc_type     buftype)  /* I/O buffer type */
{
    int indx, file_ver, err, status=NC_NOERR, mpireturn;
    NC *ncp;
    NC_attrarray *ncap;
    NC_attr *attrp, *old=NULL;

    if (!name || strlen(name) > NC_MAX_NAME)
        return NC_EBADNAME;

    /* Should CDF-5 allow very large file header? */
    /* if (len > X_INT_MAX) return NC_EINVAL; */

    /* get the file ID */
    status = ncmpii_NC_check_id(ncid, &ncp);
    if (status != NC_NOERR) return status;

    /* file should be opened with writable permission */
    if (NC_readonly(ncp)) return NC_EPERM;

    /* nelems can be zero, i.e. an attribute with only its name */
    if (nelems > 0 && buf == NULL)
        return NC_EINVAL; /* Null arg */

    /* If this is the _FillValue attribute, then let PnetCDF return the
     * same error codes as netCDF
     */
    if (!strcmp(name, "_FillValue")) {
        NC_var *varp;
        status = ncmpii_NC_lookupvar(ncp, varid, &varp);
        if (status != NC_NOERR) return status;

        /* Fill value must be same type and have exactly one value */
        if (filetype != varp->type)
            return NC_EBADTYPE;

        if (nelems != 1)
            return NC_EINVAL;
    }

    /* get the file format version */
    file_ver = 1;
    if (fIsSet(ncp->flags, NC_64BIT_OFFSET))
        file_ver = 2;
    else if (fIsSet(ncp->flags, NC_64BIT_DATA))
        file_ver = 5;

    if (nelems < 0 || (nelems > X_INT_MAX && file_ver <= 2))
        return NC_EINVAL; /* Invalid nelems */

    /* check if filetype is valid, as filetype is given by user
     * no need to check buftype, as buftype is set internally
     */
    status = ncmpii_cktype(file_ver, filetype);
    if (status != NC_NOERR) return status;

    /* No character conversions are allowed. */
    if (filetype != buftype &&
        (filetype == NC_CHAR || buftype == NC_CHAR))
        return NC_ECHAR;

    /* check if the attribute name is legal */
    status = ncmpii_NC_check_name(name, file_ver);
    if (status != NC_NOERR) return status;

    /* get the pointer to the attribute array */
    ncap = NC_attrarray0(ncp, varid);
    if (ncap == NULL) return NC_ENOTVAR;

    indx = ncmpii_NC_findattr(ncap, name);
    if (indx >= 0) { /* name in use */
        if (!NC_indef(ncp)) {
            /* in data mode, meaning to over-write an existing attribute
             * if called in data mode (collective or independent), this
             * function must be called collectively, i.e. all processes must
             * participate
             */

            const MPI_Offset xsz = ncmpix_len_NC_attrV(filetype, nelems);
            /* xsz is the total size of this attribute */

            attrp = ncap->value[indx]; /* convenience */

            if (xsz > attrp->xsz) /* new attribute requires a larger space */
                return NC_ENOTINDEFINE;
            /* else, we can reuse existing without redef */

            if (xsz != (int)xsz) return NC_EINTOVERFLOW;

            attrp->xsz = xsz;
            attrp->type = filetype;
            attrp->nelems = nelems;

            if (nelems != 0) {
                void *xp = attrp->xvalue;
                /* using xp to prevent change the pointer attr->xvalue,
                 * as ncmpix_pad_putn() advances the first argument
                 * with nelems elements
                 */
                status = ncmpix_pad_putn(&xp, nelems, buf, filetype, buftype);
                /* wkliao: why not return here if status != NC_NOERR? */

                /* PnetCDF expects all processes use the same argument values.
                 * However, when argument values are not the same, only root's
                 * value is significant. Broadcast the new attribute at root to
                 * overwrite new attribute at other processes.
                 */
                TRACE_COMM(MPI_Bcast)(attrp->xvalue, (int)attrp->xsz, MPI_BYTE,
                                      0, ncp->nciop->comm);
                if (mpireturn != MPI_SUCCESS) {
                    err = ncmpii_handle_error(mpireturn, "MPI_Bcast"); 
                    if (status == NC_NOERR) status = err;
                }
            }

            /* Let root write the entire header to the file. Note that we
             * cannot just update the attribute in its space occupied in the
             * file header, because if the file space occupied by the attribute
             * shrinks, all the metadata following it must be moved ahead.
             */
            err = ncmpii_write_header(ncp);
            return (status == NC_NOERR) ? err : status;
        }
        /* else, redefine using existing array slot */
        old = ncap->value[indx];
    }
    else { /* name never been used */
        /* creating new attributes must be done in define mode */
        if (!NC_indef(ncp)) return NC_ENOTINDEFINE;

        if (ncap->ndefined >= NC_MAX_ATTRS)
            return NC_EMAXATTS;
    }

    /* create a new attribute object */
    attrp = ncmpii_new_NC_attr(name, filetype, nelems);
    if (attrp == NULL) return NC_ENOMEM;

    if (nelems != 0) { /* non-zero length attribute */
        void *xp = attrp->xvalue;
        status = ncmpix_pad_putn(&xp, nelems, buf, filetype, buftype);
        /* wkliao: no immediately return error code here? Strange ... 
         *         Instead, we continue and call incr_NC_attrarray() to add
         *         this attribute (for create case) as it is legal. But if
         *         we return error and reject this attribute, then nc_test will
         *         fail with this error message below:
         *         FAILURE at line 252 of test_read.c: ncmpi_inq: wrong number
         *         of global atts returned, 3
         *         Check netCDF-4, it is doing the same thing!
         *
         *         One of the error codes returned from ncmpix_pad_putn() is
         *         NC_ERANGE, meaning one or more elements are type overflow.
         *         Should we reject the entire attribute array if only part of
         *         the array overflow? For netCDF4, the answer is NO.
         */ 
/*
        if (status != NC_NOERR) {
            ncmpii_free_NC_attr(attrp);
            return status;
        }
*/
    }

    if (indx >= 0) { /* modify the existing attribute */
        assert(old != NULL);
        ncap->value[indx] = attrp;
        ncmpii_free_NC_attr(old);
    }
    else { /* creating a new attribute */
        err = incr_NC_attrarray(ncap, attrp);
        if (err != NC_NOERR) {
            ncmpii_free_NC_attr(attrp);
            return err;
        }
    }

    return status;
}

/*----< ncmpi_put_att() >-----------------------------------------------------*/
int
ncmpi_put_att(int         ncid,
              int         varid,
              const char *name,
              nc_type     xtype,
              MPI_Offset  nelems,
              const void *value)
{
    return ncmpii_put_att(ncid, varid, name, xtype, nelems, value, xtype);
}

/*----< ncmpi_put_att_text() >-----------------------------------------------*/
int
ncmpi_put_att_text(int ncid, int varid, const char *name,
                   MPI_Offset nelems, const char *value)
{
    return ncmpii_put_att(ncid, varid, name, NC_CHAR,
                          nelems, value, NC_CHAR);
}

dnl
dnl PUT_ATT_TYPE(fntype, ext_buftype, nc_buftype)
dnl
define(`PUT_ATT_TYPE',dnl
`dnl
/*----< ncmpi_put_att_$1() >-------------------------------------------------*/
int
ncmpi_put_att_$1(int ncid, int varid, const char *name, nc_type xtype,
                 MPI_Offset nelems, const $2 *value)
{
    return ncmpii_put_att(ncid, varid, name, xtype, nelems, value, $3);
}
')dnl

PUT_ATT_TYPE(schar,     signed char,        NC_BYTE)
PUT_ATT_TYPE(uchar,     unsigned char,      NC_UBYTE)
PUT_ATT_TYPE(ubyte,     unsigned char,      NC_UBYTE)
PUT_ATT_TYPE(short,     short,              NC_SHORT)
PUT_ATT_TYPE(ushort,    unsigned short,     NC_USHORT)
PUT_ATT_TYPE(int,       int,                NC_INT)
PUT_ATT_TYPE(uint,      unsigned int,       NC_UINT)
PUT_ATT_TYPE(long,      long,               longtype)
PUT_ATT_TYPE(float,     float,              NC_FLOAT)
PUT_ATT_TYPE(double,    double,             NC_DOUBLE)
PUT_ATT_TYPE(longlong,  long long,          NC_INT64)
PUT_ATT_TYPE(ulonglong, unsigned long long, NC_UINT64)

/* For netCDF, the type mapping between file types and buffer types
 * are based on netcdf4. Check APIs of nc_put_att_xxx from source files
 *     netCDF/netcdf-4.1.3/libdispatch/att.c
 *     netCDF/netcdf-4.1.3/libsrc4/nc4attr.c
 *
 * Note that schar means signed 1-byte integers in attributes. Hence the call
 * below is illegal. NC_ECHAR will return, indicating the error on trying
 * type conversion between characters and numbers.
 *
 * ncmpi_put_att_schar(ncid, varid, "attr name", NC_CHAR, strlen(attrp), attrp);
 *
 * This rule and mapping apply for variables as well. See APIs of
 * nc_put_vara_xxx from source files
 *     netCDF/netcdf-4.1.3/libdispatch/var.c
 *     netCDF/netcdf-4.1.3/libsrc4/nc4var.c
 *
 */
