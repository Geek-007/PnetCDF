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
#define nfmpi_put_vara_text_ NFMPI_PUT_VARA_TEXT
#elif defined(F77_NAME_LOWER_2USCORE)
#define nfmpi_put_vara_text_ nfmpi_put_vara_text__
#elif !defined(F77_NAME_LOWER_USCORE)
#define nfmpi_put_vara_text_ nfmpi_put_vara_text
/* Else leave name alone */
#endif


/* Prototypes for the Fortran interfaces */
#include "mpifnetcdf.h"
FORTRAN_API void FORT_CALL nfmpi_put_vara_text_ ( int *v1, int *v2, int v3[], int v4[], char *v5 FORT_MIXED_LEN(d5), MPI_Fint *ierr FORT_END_LEN(d5) ){
    size_t *l3;
    size_t *l4;
    char *p5;

    { int ln = ncxVardim(*v1,*v2);
    if (ln > 0) {
        int li;
        l3 = (size_t *)malloc( ln * sizeof(size_t) );
        for (li=0; li<ln; li++) 
            l3[li] = v3[ln-1-li];
    }

    { int ln = ncxVardim(*v1,*v2);
    if (ln > 0) {
        int li;
        l4 = (size_t *)malloc( ln * sizeof(size_t) );
        for (li=0; li<ln; li++) 
            l4[li] = v4[ln-1-li];
    }

    {char *p = v5 + d5 - 1;
     int  li;
        while (*p == ' ' && p > v5) p--;
        p++;
        p5 = (char *)malloc( p-v5 + 1 );
        for (li=0; li<(p-v5); li++) { p5[li] = v5[li]; }
        p5[li] = 0; 
    }
    *ierr = ncmpi_put_vara_text( *v1, *v2, l3, l4, p5 );

    if (l3) { free(l3); }
    free( p5 );

    if (l4) { free(l4); }
}
