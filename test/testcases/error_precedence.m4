dnl Process this m4 file to produce 'C' language file.
dnl
dnl If you see this line, you can ignore the next one.
/* Do not edit this file. It is produced from the corresponding .m4 source */
dnl
/*********************************************************************
 *
 *  Copyright (C) 2018, Northwestern University and Argonne National Laboratory
 *  See COPYRIGHT notice in top-level directory.
 *
 *********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h> /* strcpy(), strncpy() */
#include <libgen.h> /* basename() */

/* This program can also be used to test NetCDF.
 * Add #define TEST_NETCDF and compile with command:
 * gcc -I/netcdf/path/include last_large_var.c -o last_large_var -L/netcdf/path/lib -lnetcdf
 */
define(`IntType', `ifdef(`TEST_NETCDF',`MPI_Offset',`size_t')')dnl
define(`PTRDType',`ifdef(`TEST_NETCDF',`MPI_Offset',`ptrdiff_t')')dnl
define(`API', `ifdef(`TEST_NETCDF',`nc_$1',`ncmpi_$1')')dnl

define(`FileOpen',  `ifdef(`TEST_NETCDF',`nc_open($1,$2,$3)',`ncmpi_open(comm,$1,$2,info,$3)')')dnl
define(`FileCreate',`ifdef(`TEST_NETCDF',`nc_create($1,$2,$3)',`ncmpi_create(comm, $1, $2, info, $3)')')dnl

define(`GetVar1TYPE',`ifdef(`TEST_NETCDF',`ncmpi_get_var1_$1_all',`nc_get_var1_$1')')dnl
define(`PutVar1TYPE',`ifdef(`TEST_NETCDF',`ncmpi_put_var1_$1_all',`nc_put_var1_$1')')dnl

define(`PutVar1', `ifdef(`TEST_NETCDF',`ncmpi_put_var1_all($1,$2,$3,$4,$5,$6)',          `nc_put_var1($1,$2,$3,$4)')')dnl
define(`PutVar',  `ifdef(`TEST_NETCDF',`ncmpi_put_var_all( $1,$2,$3,$4,$5)',             `nc_put_var( $1,$2,$3)')')dnl
define(`PutVara', `ifdef(`TEST_NETCDF',`ncmpi_put_vara_all($1,$2,$3,$4,$5,$6,$7)',       `nc_put_vara($1,$2,$3,$4,$5)')')dnl
define(`PutVars', `ifdef(`TEST_NETCDF',`ncmpi_put_vars_all($1,$2,$3,$4,$5,$6,$7,$8)',    `nc_put_vars($1,$2,$3,$4,$5,$6)')')dnl
define(`PutVarm', `ifdef(`TEST_NETCDF',`ncmpi_put_varm_all($1,$2,$3,$4,$5,$6,$7,$8,$9)', `nc_put_varm($1,$2,$3,$4,$5,$6,$7)')')dnl


#ifdef TEST_NETCDF
#include <netcdf.h>
#include <netcdf_meta.h>
#define CHECK_ERR { \
    if (err != NC_NOERR) { \
        nerrs++; \
        printf("Error at line %d in %s: (%s)\n", \
        __LINE__,__FILE__,nc_strerror(err)); \
    } \
}
#define EXP_ERR(exp) { \
    if (err != exp) { \
        nerrs++; \
        printf("Error at line %d in %s: expecting %d but got %d\n", \
        __LINE__,__FILE__,exp, err); \
    } \
}
#define SetFill                 nc_set_fill
#define ReDef                   nc_redef
#define EndDef                  nc_enddef
#define _EndDef                 nc__enddef
#define FileClose               nc_close
#define StrError                nc_strerror
#define MPI_Init(a,b)
#define MPI_Comm_rank(a,b)
#define MPI_Comm_size(a,b)
#define MPI_Finalize()
#define MPI_Bcast(a,b,c,d,e)
#else
#include <pnetcdf.h>
#include <testutils.h>
#define SetFill         ncmpi_set_fill
#define ReDef           ncmpi_redef
#define EndDef          ncmpi_enddef
#define _EndDef         ncmpi__enddef
#define FileClose       ncmpi_close
#define StrError        ncmpi_strerror
#endif


#define Y_LEN 7
#define X_LEN 5

static int verbose;

include(`foreach.m4')dnl
include(`utils.m4')dnl

#define text char
#ifndef schar
#define schar signed char
#endif
#ifndef uchar
#define uchar unsigned char
#endif
#ifndef ushort
#define ushort unsigned short
#endif
#ifndef uint
#define uint unsigned int
#endif
#ifndef longlong
#define longlong long long
#endif
#ifndef ulonglong
#define ulonglong unsigned long long
#endif

define(`CDF5_ITYPES',`schar,uchar,short,ushort,int,uint,long,float,double,longlong,ulonglong')dnl
define(`CDF2_ITYPES',`schar,short,int,long,float,double')dnl
define(`EXTRA_ITYPES',`uchar,ushort,uint,longlong,ulonglong')dnl

define(`TEST_FORMAT',dnl
`dnl
static int
test_format_nc$1(char *filename)
{
    int err, nerrs=0, ncid, cmode, dimids[2];
    MPI_Comm comm=MPI_COMM_WORLD;
    MPI_Info info=MPI_INFO_NULL;
    MPI_Offset start[2], count[2], stride[2], imap[2];

    /* NC_FORMAT_NETCDF4_CLASSIC does not support extended data types, i.e. NC_UINT, NC_INT64 etc. */
    define(`TYPE_LIST',`ifelse(`$1',`5',`CDF5_ITYPES',`$1',`3',`CDF5_ITYPES',`CDF2_ITYPES')')dnl

    /* variable IDs */dnl
    foreach(`itype',(text,TYPE_LIST),`
    _CAT(`int vid_',itype);')

    /* variable buffers */dnl
    foreach(`itype',(text,TYPE_LIST),`
    _CAT(itype itype,`_buf[3];')')dnl

    dnl constants defined in netcdf.h and pnetcdf.h
    dnl #define NC_FORMAT_CLASSIC         (1)
    dnl #define NC_FORMAT_64BIT_OFFSET    (2)
    dnl #define NC_FORMAT_NETCDF4         (3)
    dnl #define NC_FORMAT_NETCDF4_CLASSIC (4)
    dnl #define NC_FORMAT_64BIT_DATA      (5)

    /* create a new file */
    ifelse(`$1',`2',`cmode = NC_CLOBBER | NC_64BIT_OFFSET;',
           `$1',`5',`cmode = NC_CLOBBER | NC_64BIT_DATA;',
           `$1',`3',`cmode = NC_CLOBBER | NC_NETCDF4;',
           `$1',`4',`cmode = NC_CLOBBER | NC_NETCDF4 | NC_CLASSIC_MODEL;',
                    `cmode = NC_CLOBBER;')dnl

    err=FileCreate(filename, cmode, &ncid);
    if (err != NC_NOERR) {
        printf("Error at line %d in %s: FileCreate() file %s (%s)\n",
        __LINE__,__FILE__,filename,StrError(err));
        MPI_Abort(MPI_COMM_WORLD, -1);
        exit(1);
    }

    /* test NC_EBADID */
    err=API(def_dim)(-999,NULL,-100,NULL);         EXP_ERR(NC_EBADID)
    err=API(def_var)(-999,NULL,-100,-1,NULL,NULL); EXP_ERR(NC_EBADID)

    /* test NC_EBADNAME */
    err=API(def_dim)(ncid,NULL,-100,NULL);         EXP_ERR(NC_EBADNAME)
    err=API(def_var)(ncid,NULL,-100,-1,NULL,NULL); EXP_ERR(NC_EBADNAME)

    /* test NC_EDIMSIZE */
    err=API(def_dim)(ncid,"Y",-100,NULL); EXP_ERR(NC_EDIMSIZE)

    /* define dimensions */
    err=API(def_dim)(ncid,"Y",Y_LEN,&dimids[0]); CHECK_ERR
    err=API(def_dim)(ncid,"X",X_LEN,&dimids[1]); CHECK_ERR

    /* test NC_EBADTYPE */
    err=API(def_var)(ncid,"var",-100,-1,NULL,NULL); EXP_ERR(NC_EBADTYPE)

    /* define variables */dnl
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(def_var)(ncid,"var_'itype`",NC_TYPE(itype),2,dimids,&vid_',itype`); CHECK_ERR')')

/*
      For put attribute APIs:
          NC_EBADID, NC_EPERM, NC_ENOTVAR, NC_EBADNAME, NC_EBADTYPE, NC_ECHAR,
          NC_EINVAL, NC_ENOTINDEFINE, NC_ERANGE
      For get attribute APIs:
          NC_EBADID, NC_ENOTVAR, NC_EBADNAME, NC_ENOTATT, NC_ECHAR, NC_EINVAL,
          NC_ERANGE
      For put/get variable APIs:
          NC_EBADID, NC_EPERM, NC_EINDEFINE, NC_ENOTVAR, NC_ECHAR,
          NC_EINVALCOORDS, NC_EEDGE, NC_ESTRIDE, NC_EINVAL, NC_ERANGE
*/

    /* test attribute APIs */
    err=API(put_att_text) (-999,-999,NULL,-999,NULL);           EXP_ERR(NC_EBADID)
    err=API(put_att_text) (ncid,-999,NULL,-999,NULL);           EXP_ERR(NC_ENOTVAR)
    err=API(put_att_text) (ncid,vid_text,NULL,-999,NULL);       EXP_ERR(NC_EBADNAME)
    err=API(put_att_text) (ncid,vid_text,"att_text",-999,NULL); EXP_ERR(NC_EINVAL)
    err=API(put_att_text) (ncid,vid_text,"att_text",3,NULL);    EXP_ERR(NC_EINVAL)
    err=API(put_att_text) (ncid,vid_text,"att_text",0,NULL);    CHECK_ERR
    err=API(put_att_text) (ncid,vid_text,"att_text",3,"abc");   CHECK_ERR

    err=API(get_att)      (-999,-999,NULL,NULL);                EXP_ERR(NC_EBADID)
    err=API(get_att_text) (-999,-999,NULL,NULL);                EXP_ERR(NC_EBADID)
    err=API(get_att)      (ncid,-999,NULL,NULL);                EXP_ERR(NC_ENOTVAR)
    err=API(get_att_text) (ncid,-999,NULL,NULL);                EXP_ERR(NC_ENOTVAR)
    err=API(get_att)      (ncid,vid_text,NULL,NULL);            EXP_ERR(NC_EBADNAME)
    err=API(get_att_text) (ncid,vid_text,NULL,NULL);            EXP_ERR(NC_EBADNAME)
    err=API(get_att)      (ncid,vid_text,"att_text",NULL);      EXP_ERR(NC_EINVAL)
    err=API(get_att_text) (ncid,vid_text,"att_text",NULL);      EXP_ERR(NC_EINVAL)

    foreach(`itype',(TYPE_LIST),`_CAT(`
    err=API(put_att)        (-999,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EBADID)
    err=API(put_att_'itype`)(-999,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EBADID)
    err=API(put_att)        (ncid,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_ENOTVAR)
    err=API(put_att_'itype`)(ncid,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_ENOTVAR)
    err=API(put_att)        (ncid,vid_'itype`,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EBADNAME)
    err=API(put_att_'itype`)(ncid,vid_'itype`,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EBADNAME)
    err=API(put_att)        (ncid,vid_'itype`,`"att_'itype`"',NC_NAT,-999,NULL); EXP_ERR(NC_EBADTYPE)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_NAT,-999,NULL); EXP_ERR(NC_EBADTYPE)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_CHAR,-999,NULL); EXP_ERR(NC_ECHAR)
    err=API(put_att)        (ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),-999,NULL); EXP_ERR(NC_EINVAL)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),-999,NULL); EXP_ERR(NC_EINVAL)
    err=API(put_att)        (ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),1,NULL); EXP_ERR(NC_EINVAL)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),1,NULL); EXP_ERR(NC_EINVAL)
    err=API(put_att)        (ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),0,NULL); CHECK_ERR
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),0,NULL); CHECK_ERR
    itype`_buf[0]' = (itype)1;
    itype`_buf[1]' = (itype)2;
    itype`_buf[2]' = (itype)3;
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),3,itype`_buf'); CHECK_ERR

    err=API(get_att)        (-999,-999,NULL,NULL); EXP_ERR(NC_EBADID)
    err=API(get_att_'itype`)(-999,-999,NULL,NULL); EXP_ERR(NC_EBADID)
    err=API(get_att)        (ncid,-999,NULL,NULL); EXP_ERR(NC_ENOTVAR)
    err=API(get_att_'itype`)(ncid,-999,NULL,NULL); EXP_ERR(NC_ENOTVAR)
    err=API(get_att)        (ncid,vid_'itype`,NULL,NULL); EXP_ERR(NC_EBADNAME)
    err=API(get_att_'itype`)(ncid,vid_'itype`,NULL,NULL); EXP_ERR(NC_EBADNAME)
    err=API(get_att)        (ncid,vid_'itype`,"fairy",NULL); EXP_ERR(NC_ENOTATT)
    err=API(get_att_'itype`)(ncid,vid_'itype`,"fairy",NULL); EXP_ERR(NC_ENOTATT)
    err=API(get_att_'itype`)(ncid,vid_text,"att_text",NULL);         EXP_ERR(NC_ECHAR)
    err=API(get_att_text)   (ncid,vid_'itype`,`"att_'itype`"',NULL); EXP_ERR(NC_ECHAR)
    err=API(get_att)        (ncid,vid_'itype`,`"att_'itype`"',NULL); EXP_ERR(NC_EINVAL)
    err=API(get_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NULL); EXP_ERR(NC_EINVAL)
')')

    /* test delete attribute API */
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(del_att)(-999,-999,NULL);                   EXP_ERR(NC_EBADID)
    err=API(del_att)(ncid,-999,NULL);                   EXP_ERR(NC_ENOTVAR)
    err=API(del_att)(ncid,vid_'itype`,NULL);            EXP_ERR(NC_EBADNAME)
    err=API(del_att)(ncid,vid_'itype`,`"att_'itype`"'); CHECK_ERR')')

    /* test put_var APIs in define mode */
    ifelse(`$1',`3',`',`/* test NC_EINDEFINE */dnl
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(put_var_'itype`_all) (ncid,-999,NULL);                     EXP_ERR(NC_EINDEFINE)
    err=API(put_var1_'itype`_all)(ncid,-999,NULL,NULL);                EXP_ERR(NC_EINDEFINE)
    err=API(put_vara_'itype`_all)(ncid,-999,NULL,NULL,NULL);           EXP_ERR(NC_EINDEFINE)
    err=API(put_vars_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL);      EXP_ERR(NC_EINDEFINE)
    err=API(put_varm_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL,NULL); EXP_ERR(NC_EINDEFINE)')')')

    /* test put_var APIs in define mode */
    ifelse(`$1',`3',`',`/* test NC_EINDEFINE */dnl
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(get_var_'itype`_all) (ncid,-999,NULL);                     EXP_ERR(NC_EINDEFINE)
    err=API(get_var1_'itype`_all)(ncid,-999,NULL,NULL);                EXP_ERR(NC_EINDEFINE)
    err=API(get_vara_'itype`_all)(ncid,-999,NULL,NULL,NULL);           EXP_ERR(NC_EINDEFINE)
    err=API(get_vars_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL);      EXP_ERR(NC_EINDEFINE)
    err=API(get_varm_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL,NULL); EXP_ERR(NC_EINDEFINE)')')')

    /* test NC_EBADID */
    err=EndDef(-999); EXP_ERR(NC_EBADID)
    err=ReDef(-999);  EXP_ERR(NC_EBADID)

    /* leave define mode and enter data mode */
    err=EndDef(ncid); CHECK_ERR

    /* attribute att_text has been deleted */
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(inq_att)(ncid,vid_'itype`,`"att_'itype`"',NULL,NULL); EXP_ERR(NC_ENOTATT)')')

    ifelse(`$1',`3',`',`dnl
    /* test NC_ENOTINDEFINE */
    err=API(def_dim)(-999,NULL,-100,NULL); EXP_ERR(NC_EBADID)
    err=API(def_dim)(ncid,NULL,-100,NULL); EXP_ERR(NC_ENOTINDEFINE)
    err=API(def_dim)(ncid,"Z", -100,NULL); EXP_ERR(NC_ENOTINDEFINE)
    err=API(def_dim)(ncid,"Z",  100,NULL); EXP_ERR(NC_ENOTINDEFINE)

    err=API(def_var)(-999,NULL, -100,  -1,NULL,  NULL); EXP_ERR(NC_EBADID)
    err=API(def_var)(ncid,NULL, -100,  -1,NULL,  NULL); EXP_ERR(NC_ENOTINDEFINE)
    err=API(def_var)(ncid,"var",-100,  -1,NULL,  NULL); EXP_ERR(NC_ENOTINDEFINE)
    err=API(def_var)(ncid,"var",NC_INT,-1,NULL,  NULL); EXP_ERR(NC_ENOTINDEFINE)
    err=API(def_var)(ncid,"var",NC_INT, 2,NULL,  NULL); EXP_ERR(NC_ENOTINDEFINE)
    err=API(def_var)(ncid,"var",NC_INT, 2,dimids,NULL); EXP_ERR(NC_ENOTINDEFINE)

    /* NC_FORMAT_NETCDF4 allows defining new attributes in data mode, but not classic formats */
    err=API(put_att_text) (ncid,vid_text,"att_text",0,NULL);  EXP_ERR(NC_ENOTINDEFINE)
    err=API(put_att_text) (ncid,vid_text,"att_text",3,"abc"); EXP_ERR(NC_ENOTINDEFINE)')

    /* test NC_EBADID */dnl
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(put_var_'itype`_all) (-999,-999,NULL);                     EXP_ERR(NC_EBADID)
    err=API(put_var1_'itype`_all)(-999,-999,NULL,NULL);                EXP_ERR(NC_EBADID)
    err=API(put_vara_'itype`_all)(-999,-999,NULL,NULL,NULL);           EXP_ERR(NC_EBADID)
    err=API(put_vars_'itype`_all)(-999,-999,NULL,NULL,NULL,NULL);      EXP_ERR(NC_EBADID)
    err=API(put_varm_'itype`_all)(-999,-999,NULL,NULL,NULL,NULL,NULL); EXP_ERR(NC_EBADID)
    err=API(get_var_'itype`_all) (-999,-999,NULL);                     EXP_ERR(NC_EBADID)
    err=API(get_var1_'itype`_all)(-999,-999,NULL,NULL);                EXP_ERR(NC_EBADID)
    err=API(get_vara_'itype`_all)(-999,-999,NULL,NULL,NULL);           EXP_ERR(NC_EBADID)
    err=API(get_vars_'itype`_all)(-999,-999,NULL,NULL,NULL,NULL);      EXP_ERR(NC_EBADID)
    err=API(get_varm_'itype`_all)(-999,-999,NULL,NULL,NULL,NULL,NULL); EXP_ERR(NC_EBADID)
')')

    /* test NC_ENOTVAR */dnl
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(put_var_'itype`_all) (ncid,-999,NULL);                     EXP_ERR(NC_ENOTVAR)
    err=API(put_var1_'itype`_all)(ncid,-999,NULL,NULL);                EXP_ERR(NC_ENOTVAR)
    err=API(put_vara_'itype`_all)(ncid,-999,NULL,NULL,NULL);           EXP_ERR(NC_ENOTVAR)
    err=API(put_vars_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL);      EXP_ERR(NC_ENOTVAR)
    err=API(put_varm_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL,NULL); EXP_ERR(NC_ENOTVAR)
    err=API(get_var_'itype`_all) (ncid,-999,NULL);                     EXP_ERR(NC_ENOTVAR)
    err=API(get_var1_'itype`_all)(ncid,-999,NULL,NULL);                EXP_ERR(NC_ENOTVAR)
    err=API(get_vara_'itype`_all)(ncid,-999,NULL,NULL,NULL);           EXP_ERR(NC_ENOTVAR)
    err=API(get_vars_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL);      EXP_ERR(NC_ENOTVAR)
    err=API(get_varm_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL,NULL); EXP_ERR(NC_ENOTVAR)
')')

    /* test NC_EINVALCOORDS */
    start[0] = Y_LEN;
    start[1] = X_LEN;
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(put_var1_'itype`_all)(ncid,vid_'itype`,NULL,NULL);                 EXP_ERR(NC_EINVALCOORDS)
    err=API(put_vara_'itype`_all)(ncid,vid_'itype`,NULL,NULL,NULL);            EXP_ERR(NC_EINVALCOORDS)
    err=API(put_vars_'itype`_all)(ncid,vid_'itype`,NULL,NULL,NULL,NULL);       EXP_ERR(NC_EINVALCOORDS)
    err=API(put_varm_'itype`_all)(ncid,vid_'itype`,NULL,NULL,NULL,NULL,NULL);  EXP_ERR(NC_EINVALCOORDS)
    err=API(put_var1_'itype`_all)(ncid,vid_'itype`,start,NULL);                EXP_ERR(NC_EINVALCOORDS)
    err=API(put_vara_'itype`_all)(ncid,vid_'itype`,start,NULL,NULL);           EXP_ERR(NC_EINVALCOORDS)
    err=API(put_vars_'itype`_all)(ncid,vid_'itype`,start,NULL,NULL,NULL);      EXP_ERR(NC_EINVALCOORDS)
    err=API(put_varm_'itype`_all)(ncid,vid_'itype`,start,NULL,NULL,NULL,NULL); EXP_ERR(NC_EINVALCOORDS)
    err=API(get_var1_'itype`_all)(ncid,vid_'itype`,NULL,NULL);                 EXP_ERR(NC_EINVALCOORDS)
    err=API(get_vara_'itype`_all)(ncid,vid_'itype`,NULL,NULL,NULL);            EXP_ERR(NC_EINVALCOORDS)
    err=API(get_vars_'itype`_all)(ncid,vid_'itype`,NULL,NULL,NULL,NULL);       EXP_ERR(NC_EINVALCOORDS)
    err=API(get_varm_'itype`_all)(ncid,vid_'itype`,NULL,NULL,NULL,NULL,NULL);  EXP_ERR(NC_EINVALCOORDS)
    err=API(get_var1_'itype`_all)(ncid,vid_'itype`,start,NULL);                EXP_ERR(NC_EINVALCOORDS)
    err=API(get_vara_'itype`_all)(ncid,vid_'itype`,start,NULL,NULL);           EXP_ERR(NC_EINVALCOORDS)
    err=API(get_vars_'itype`_all)(ncid,vid_'itype`,start,NULL,NULL,NULL);      EXP_ERR(NC_EINVALCOORDS)
    err=API(get_varm_'itype`_all)(ncid,vid_'itype`,start,NULL,NULL,NULL,NULL); EXP_ERR(NC_EINVALCOORDS)
')')

    /* test NC_EEDGE */
    start[0] = 0;
    start[1] = 0;
    count[0] = Y_LEN;
    count[1] = X_LEN + 1;
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(put_vara_'itype`_all)(ncid,vid_'itype`,start,NULL, NULL);           EXP_ERR(NC_EEDGE)
    err=API(put_vars_'itype`_all)(ncid,vid_'itype`,start,NULL, NULL,NULL);      EXP_ERR(NC_EEDGE)
    err=API(put_varm_'itype`_all)(ncid,vid_'itype`,start,NULL, NULL,NULL,NULL); EXP_ERR(NC_EEDGE)
    err=API(put_vara_'itype`_all)(ncid,vid_'itype`,start,count,NULL);           EXP_ERR(NC_EEDGE)
    err=API(put_vars_'itype`_all)(ncid,vid_'itype`,start,count,NULL,NULL);      EXP_ERR(NC_EEDGE)
    err=API(put_varm_'itype`_all)(ncid,vid_'itype`,start,count,NULL,NULL,NULL); EXP_ERR(NC_EEDGE)
    err=API(get_vara_'itype`_all)(ncid,vid_'itype`,start,NULL, NULL);           EXP_ERR(NC_EEDGE)
    err=API(get_vars_'itype`_all)(ncid,vid_'itype`,start,NULL, NULL,NULL);      EXP_ERR(NC_EEDGE)
    err=API(get_varm_'itype`_all)(ncid,vid_'itype`,start,NULL, NULL,NULL,NULL); EXP_ERR(NC_EEDGE)
    err=API(get_vara_'itype`_all)(ncid,vid_'itype`,start,count,NULL);           EXP_ERR(NC_EEDGE)
    err=API(get_vars_'itype`_all)(ncid,vid_'itype`,start,count,NULL,NULL);      EXP_ERR(NC_EEDGE)
    err=API(get_varm_'itype`_all)(ncid,vid_'itype`,start,count,NULL,NULL,NULL); EXP_ERR(NC_EEDGE)
')')

    /* test NC_ESTRIDE */
    start[0] = start[1] = 0;
    count[0] = Y_LEN;
    count[1] = X_LEN;
    stride[0] = -1;
    stride[1] = -1;
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(put_vars_'itype`_all)(ncid,vid_'itype`,start,count,stride,NULL);      EXP_ERR(NC_ESTRIDE)
    err=API(put_varm_'itype`_all)(ncid,vid_'itype`,start,count,stride,NULL,NULL); EXP_ERR(NC_ESTRIDE)
    err=API(get_vars_'itype`_all)(ncid,vid_'itype`,start,count,stride,NULL);      EXP_ERR(NC_ESTRIDE)
    err=API(get_varm_'itype`_all)(ncid,vid_'itype`,start,count,stride,NULL,NULL); EXP_ERR(NC_ESTRIDE)
')')

    /* close the file */
    err=FileClose(-999); EXP_ERR(NC_EBADID)
    err=FileClose(ncid); CHECK_ERR

    /* open the file with read-only permission */
    err=FileOpen(filename, NC_NOWRITE, &ncid);
    if (err != NC_NOERR) {
        printf("Error at line %d in %s: FileOpen() file %s (%s)\n",
        __LINE__,__FILE__,filename,StrError(err));
        MPI_Abort(MPI_COMM_WORLD, -1);
        exit(1);
    }

    /* test NC_EPERM */
    err=ReDef(ncid); EXP_ERR(NC_EPERM)

    /* test NC_EPERM for attribute APIs */dnl
    err=API(put_att_text) (-999,-999,NULL,-999,NULL);           EXP_ERR(NC_EBADID)
    err=API(put_att_text) (ncid,-999,NULL,-999,NULL);           EXP_ERR(NC_EPERM)
    err=API(put_att_text) (ncid,vid_text,NULL,-999,NULL);       EXP_ERR(NC_EPERM)
    err=API(put_att_text) (ncid,vid_text,"att_text",-999,NULL); EXP_ERR(NC_EPERM)
    foreach(`itype',(TYPE_LIST),`_CAT(`
    err=API(put_att)        (-999,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EBADID)
    err=API(put_att_'itype`)(-999,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EBADID)
    err=API(put_att)        (ncid,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att_'itype`)(ncid,-999,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att)        (ncid,vid_'itype`,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att_'itype`)(ncid,vid_'itype`,NULL,NC_NAT,-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att)        (ncid,vid_'itype`,`"att_'itype`"',NC_NAT,-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_NAT,-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_CHAR,-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att)        (ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),-999,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att)        (ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),1,NULL); EXP_ERR(NC_EPERM)
    err=API(put_att_'itype`)(ncid,vid_'itype`,`"att_'itype`"',NC_TYPE(itype),1,NULL); EXP_ERR(NC_EPERM)')')

    /* test NC_EPERM */dnl
    foreach(`itype',(text, TYPE_LIST),`_CAT(`
    err=API(put_var_'itype`_all) (ncid,-999,NULL);                     EXP_ERR(NC_EPERM)
    err=API(put_var1_'itype`_all)(ncid,-999,NULL,NULL);                EXP_ERR(NC_EPERM)
    err=API(put_vara_'itype`_all)(ncid,-999,NULL,NULL,NULL);           EXP_ERR(NC_EPERM)
    err=API(put_vars_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL);      EXP_ERR(NC_EPERM)
    err=API(put_varm_'itype`_all)(ncid,-999,NULL,NULL,NULL,NULL,NULL); EXP_ERR(NC_EPERM)')')

/*
      For put attribute APIs:
          NC_EBADID, NC_EPERM, NC_ENOTVAR, NC_EBADNAME, NC_EBADTYPE, NC_ECHAR,
          NC_EINVAL, NC_ENOTINDEFINE, NC_ERANGE
      For get attribute APIs:
          NC_EBADID, NC_ENOTVAR, NC_EBADNAME, NC_ENOTATT, NC_ECHAR, NC_EINVAL,
          NC_ERANGE
      For put/get variable APIs:
          NC_EBADID, NC_EPERM, NC_EINDEFINE, NC_ENOTVAR, NC_ECHAR,
          NC_EINVALCOORDS, NC_EEDGE, NC_ESTRIDE, NC_EINVAL, NC_ERANGE
*/

    /* close the file */
    err=FileClose(-999); EXP_ERR(NC_EBADID)
    err=FileClose(ncid); CHECK_ERR

    if (verbose) {
        printf("testing ifelse(`$1',`1',`NC_FORMAT_CLASSIC',
                               `$1',`2',`NC_FORMAT_64BIT_OFFSET',
                               `$1',`3',`NC_FORMAT_NETCDF4',
                               `$1',`4',`NC_FORMAT_NETCDF4_CLASSIC',
                               `$1',`5',`NC_FORMAT_64BIT_DATA') ---");
        if (nerrs == 0)
            printf("pass\n");
        else
            printf("fail\n");
    }
    return nerrs;
}
')dnl

TEST_FORMAT(1)
TEST_FORMAT(2)
TEST_FORMAT(5)
TEST_FORMAT(3)
TEST_FORMAT(4)

/*----< main() >------------------------------------------------------------*/
int main(int argc, char **argv)
{
    char filename[256];
    int rank, nprocs, err, nerrs=0;
/*
    int   fflags[4]={0, NC_64BIT_OFFSET, NC_64BIT_DATA, NC_NETCDF4};
    char *fmats[4]={"NC_FORMAT_CLASSIC",
                    "NC_FORMAT_64BIT_OFFSET",
                    "NC_FORMAT_CDF5",
                    "NC_FORMAT_NETCDF4"};
    int formats[4]={NC_FORMAT_CLASSIC,
                    NC_FORMAT_64BIT_OFFSET,
                    NC_FORMAT_CDF5,
                    NC_FORMAT_NETCDF4};
*/

    MPI_Init(&argc,&argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &nprocs);

    if (argc > 2) {
        if (!rank) printf("Usage: %s [filename]\n",argv[0]);
        MPI_Finalize();
        return 1;
    }
    if (argc == 2) snprintf(filename, 256, "%s", argv[1]);
    else           strcpy(filename, "testfile.nc");
    MPI_Bcast(filename, 256, MPI_CHAR, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        char *cmd_str = (char*)malloc(strlen(argv[0]) + 256);
        sprintf(cmd_str, "*** TESTING C   %s for error precedence ", basename(argv[0]));
        printf("%-66s ------ ", cmd_str); fflush(stdout);
        free(cmd_str);
    }
    verbose = 1;

    /* test all file formats separately */
    nerrs += test_format_nc1(filename);
    nerrs += test_format_nc2(filename);
#ifdef ENABLE_NETCDF4
    nerrs += test_format_nc3(filename); /* NC_FORMAT_NETCDF4 */
    nerrs += test_format_nc4(filename); /* NC_FORMAT_NETCDF4_CLASSIC */
#endif
    nerrs += test_format_nc5(filename);

    /* check if PnetCDF freed all internal malloc */
    MPI_Offset malloc_size, sum_size;
    err = ncmpi_inq_malloc_size(&malloc_size);
    if (err == NC_NOERR) {
        MPI_Reduce(&malloc_size, &sum_size, 1, MPI_OFFSET, MPI_SUM, 0, MPI_COMM_WORLD);
        if (rank == 0 && sum_size > 0)
            printf("heap memory allocated by PnetCDF internally has %lld bytes yet to be freed\n",
                   sum_size);
        if (malloc_size > 0) ncmpi_inq_malloc_list();
    }

    MPI_Allreduce(MPI_IN_PLACE, &nerrs, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
    if (rank == 0) {
        if (nerrs) printf(FAIL_STR,nerrs);
        else       printf(PASS_STR);
    }

    MPI_Finalize();
    return (nerrs > 0);
}

