# C language related part of Makefile.conf: Makefile.cc
C_COMPILER_NAME=cc

COMPILE.c     = cc
COMPILE.mpicc = mpicc
COMPILE.mpicxx= mpicxx

LINK.cpp = ${COMPILE.c} -lstdc++

CPPLIB = -lstdc++ -lmpi_cxx

#DEBUGC = -g

.SUFFIXES: .c .cpp

FLAGC = ${SEARCH_C} ${FLAGC_EXTRA} -c ${OPT3} ${OPENMPFLAG} ${DEBUGC}

FLAGCC = ${FLAGC} -std=c++14

.c.o:
	${COMPILE.c} ${FLAGC} $< -o $@

.cpp.o:
	${COMPILE.mpicxx} ${FLAGCC} $< -o $@
