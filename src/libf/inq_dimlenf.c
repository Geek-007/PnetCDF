/* -*- Mode: C; c-basic-offset:4 ; -*- */
/*  
 *  (C) 2001 by Argonne National Laboratory.
 *      See COPYRIGHT in top-level directory.
 *
 * This file is automatically generated by buildiface -infile=../lib/pnetcdf.h -deffile=defs
 * DO NOT EDIT
 */
#include "mpinetcdf_impl.h"


#ifdef F77_NAME_UPPER
#define nfmpi_inq_dimlen_ NFMPI_INQ_DIMLEN
#elif defined(F77_NAME_LOWER_2USCORE)
#define nfmpi_inq_dimlen_ nfmpi_inq_dimlen__
#elif !defined(F77_NAME_LOWER_USCORE)
#define nfmpi_inq_dimlen_ nfmpi_inq_dimlen
/* Else leave name alone */
#endif


/* Prototypes for the Fortran interfaces */
#include "mpifnetcdf.h"
FORTRAN_API void FORT_CALL nfmpi_inq_dimlen_ ( int *v1, int *v2, int *v3, MPI_Fint *ierr ){
    *ierr = ncmpi_inq_dimlen( *v1, *v2, v3 );
}
