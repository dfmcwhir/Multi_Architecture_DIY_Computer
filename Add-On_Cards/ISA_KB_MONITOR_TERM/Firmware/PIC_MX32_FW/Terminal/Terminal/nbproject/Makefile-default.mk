#
# Generated Makefile - do not edit!
#
# Edit the Makefile in the project folder instead (../Makefile). Each target
# has a -pre and a -post target defined where you can add customized code.
#
# This makefile implements configuration specific macros and targets.


# Include project Makefile
ifeq "${IGNORE_LOCAL}" "TRUE"
# do not include local makefile. User is passing all local related variables already
else
include Makefile
# Include makefile containing local settings
ifeq "$(wildcard nbproject/Makefile-local-default.mk)" "nbproject/Makefile-local-default.mk"
include nbproject/Makefile-local-default.mk
endif
endif

# Environment
MKDIR=gnumkdir -p
RM=rm -f 
MV=mv 
CP=cp 

# Macros
CND_CONF=default
ifeq ($(TYPE_IMAGE), DEBUG_RUN)
IMAGE_TYPE=debug
OUTPUT_SUFFIX=elf
DEBUGGABLE_SUFFIX=elf
FINAL_IMAGE=${DISTDIR}/Terminal.${IMAGE_TYPE}.${OUTPUT_SUFFIX}
else
IMAGE_TYPE=production
OUTPUT_SUFFIX=hex
DEBUGGABLE_SUFFIX=elf
FINAL_IMAGE=${DISTDIR}/Terminal.${IMAGE_TYPE}.${OUTPUT_SUFFIX}
endif

ifeq ($(COMPARE_BUILD), true)
COMPARISON_BUILD=
else
COMPARISON_BUILD=
endif

# Object Directory
OBJECTDIR=build/${CND_CONF}/${IMAGE_TYPE}

# Distribution Directory
DISTDIR=dist/${CND_CONF}/${IMAGE_TYPE}

# Source Files Quoted if spaced
SOURCEFILES_QUOTED_IF_SPACED="../USB/Microchip/USB/CDC Device Driver/usb_function_cdc.c" ../USB/Microchip/USB/usb_device.c ../USB/usb_descriptors.c ../Main.c ../Keyboard.c ../Video.c ../vt100.c

# Object Files Quoted if spaced
OBJECTFILES_QUOTED_IF_SPACED=${OBJECTDIR}/_ext/624290896/usb_function_cdc.o ${OBJECTDIR}/_ext/647448523/usb_device.o ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o ${OBJECTDIR}/_ext/1472/Main.o ${OBJECTDIR}/_ext/1472/Keyboard.o ${OBJECTDIR}/_ext/1472/Video.o ${OBJECTDIR}/_ext/1472/vt100.o
POSSIBLE_DEPFILES=${OBJECTDIR}/_ext/624290896/usb_function_cdc.o.d ${OBJECTDIR}/_ext/647448523/usb_device.o.d ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o.d ${OBJECTDIR}/_ext/1472/Main.o.d ${OBJECTDIR}/_ext/1472/Keyboard.o.d ${OBJECTDIR}/_ext/1472/Video.o.d ${OBJECTDIR}/_ext/1472/vt100.o.d

# Object Files
OBJECTFILES=${OBJECTDIR}/_ext/624290896/usb_function_cdc.o ${OBJECTDIR}/_ext/647448523/usb_device.o ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o ${OBJECTDIR}/_ext/1472/Main.o ${OBJECTDIR}/_ext/1472/Keyboard.o ${OBJECTDIR}/_ext/1472/Video.o ${OBJECTDIR}/_ext/1472/vt100.o

# Source Files
SOURCEFILES=../USB/Microchip/USB/CDC Device Driver/usb_function_cdc.c ../USB/Microchip/USB/usb_device.c ../USB/usb_descriptors.c ../Main.c ../Keyboard.c ../Video.c ../vt100.c



CFLAGS=
ASFLAGS=
LDLIBSOPTIONS=

############# Tool locations ##########################################
# If you copy a project from one host to another, the path where the  #
# compiler is installed may be different.                             #
# If you open this project with MPLAB X in the new host, this         #
# makefile will be regenerated and the paths will be corrected.       #
#######################################################################
# fixDeps replaces a bunch of sed/cat/printf statements that slow down the build
FIXDEPS=fixDeps

.build-conf:  ${BUILD_SUBPROJECTS}
ifneq ($(INFORMATION_MESSAGE), )
	@echo $(INFORMATION_MESSAGE)
endif
	${MAKE}  -f nbproject/Makefile-default.mk ${DISTDIR}/Terminal.${IMAGE_TYPE}.${OUTPUT_SUFFIX}

MP_PROCESSOR_OPTION=32MX250F128B
MP_LINKER_FILE_OPTION=,--script="..\Linker Script\32MX250F128B.ld"
# ------------------------------------------------------------------------------------
# Rules for buildStep: assemble
ifeq ($(TYPE_IMAGE), DEBUG_RUN)
else
endif

# ------------------------------------------------------------------------------------
# Rules for buildStep: assembleWithPreprocess
ifeq ($(TYPE_IMAGE), DEBUG_RUN)
else
endif

# ------------------------------------------------------------------------------------
# Rules for buildStep: compile
ifeq ($(TYPE_IMAGE), DEBUG_RUN)
${OBJECTDIR}/_ext/624290896/usb_function_cdc.o: ../USB/Microchip/USB/CDC\ Device\ Driver/usb_function_cdc.c  .generated_files/flags/default/db1ec8cd6ff959b2039e2e56de1c191a7ccfc8e3 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/624290896" 
	@${RM} ${OBJECTDIR}/_ext/624290896/usb_function_cdc.o.d 
	@${RM} ${OBJECTDIR}/_ext/624290896/usb_function_cdc.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE) -g -D__DEBUG   -fframe-base-loclist  -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/624290896/usb_function_cdc.o.d" -o ${OBJECTDIR}/_ext/624290896/usb_function_cdc.o "../USB/Microchip/USB/CDC Device Driver/usb_function_cdc.c"    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/647448523/usb_device.o: ../USB/Microchip/USB/usb_device.c  .generated_files/flags/default/ddb69e9f4632e3d41e38477100ea80e781c345df .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/647448523" 
	@${RM} ${OBJECTDIR}/_ext/647448523/usb_device.o.d 
	@${RM} ${OBJECTDIR}/_ext/647448523/usb_device.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE) -g -D__DEBUG   -fframe-base-loclist  -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/647448523/usb_device.o.d" -o ${OBJECTDIR}/_ext/647448523/usb_device.o ../USB/Microchip/USB/usb_device.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1360907413/usb_descriptors.o: ../USB/usb_descriptors.c  .generated_files/flags/default/8b58663b236163e60783758a3ea00102a07ee9d0 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1360907413" 
	@${RM} ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o.d 
	@${RM} ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE) -g -D__DEBUG   -fframe-base-loclist  -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1360907413/usb_descriptors.o.d" -o ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o ../USB/usb_descriptors.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/Main.o: ../Main.c  .generated_files/flags/default/1a54709586f5de99ec637fdadb249d66628fad37 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/Main.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/Main.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE) -g -D__DEBUG   -fframe-base-loclist  -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/Main.o.d" -o ${OBJECTDIR}/_ext/1472/Main.o ../Main.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/Keyboard.o: ../Keyboard.c  .generated_files/flags/default/1a261b959382cddb845dc48eda76ab816de055c8 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/Keyboard.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/Keyboard.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE) -g -D__DEBUG   -fframe-base-loclist  -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/Keyboard.o.d" -o ${OBJECTDIR}/_ext/1472/Keyboard.o ../Keyboard.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/Video.o: ../Video.c  .generated_files/flags/default/8e8b4102a2fcd314c34691778e532f402b4bd3fa .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/Video.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/Video.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE) -g -D__DEBUG   -fframe-base-loclist  -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/Video.o.d" -o ${OBJECTDIR}/_ext/1472/Video.o ../Video.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/vt100.o: ../vt100.c  .generated_files/flags/default/8fe0814eefb7704fe9053c4b2d3b09ac9301ade6 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/vt100.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/vt100.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE) -g -D__DEBUG   -fframe-base-loclist  -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/vt100.o.d" -o ${OBJECTDIR}/_ext/1472/vt100.o ../vt100.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
else
${OBJECTDIR}/_ext/624290896/usb_function_cdc.o: ../USB/Microchip/USB/CDC\ Device\ Driver/usb_function_cdc.c  .generated_files/flags/default/459e3ff28f84e10d5e2b5a4ece0d3843ad6f0a9 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/624290896" 
	@${RM} ${OBJECTDIR}/_ext/624290896/usb_function_cdc.o.d 
	@${RM} ${OBJECTDIR}/_ext/624290896/usb_function_cdc.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE)  -g -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/624290896/usb_function_cdc.o.d" -o ${OBJECTDIR}/_ext/624290896/usb_function_cdc.o "../USB/Microchip/USB/CDC Device Driver/usb_function_cdc.c"    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/647448523/usb_device.o: ../USB/Microchip/USB/usb_device.c  .generated_files/flags/default/100e3d9e54e4938553fd25115afe3927d9dec4cf .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/647448523" 
	@${RM} ${OBJECTDIR}/_ext/647448523/usb_device.o.d 
	@${RM} ${OBJECTDIR}/_ext/647448523/usb_device.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE)  -g -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/647448523/usb_device.o.d" -o ${OBJECTDIR}/_ext/647448523/usb_device.o ../USB/Microchip/USB/usb_device.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1360907413/usb_descriptors.o: ../USB/usb_descriptors.c  .generated_files/flags/default/9a480d23629891f6a72ac08dc1cb4d89318a7ed7 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1360907413" 
	@${RM} ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o.d 
	@${RM} ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE)  -g -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1360907413/usb_descriptors.o.d" -o ${OBJECTDIR}/_ext/1360907413/usb_descriptors.o ../USB/usb_descriptors.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/Main.o: ../Main.c  .generated_files/flags/default/c889417593f0f98808f14f731a0205a607d0544 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/Main.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/Main.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE)  -g -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/Main.o.d" -o ${OBJECTDIR}/_ext/1472/Main.o ../Main.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/Keyboard.o: ../Keyboard.c  .generated_files/flags/default/ad21d971cfd831f3096d565a01e98aa1ddc5e910 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/Keyboard.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/Keyboard.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE)  -g -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/Keyboard.o.d" -o ${OBJECTDIR}/_ext/1472/Keyboard.o ../Keyboard.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/Video.o: ../Video.c  .generated_files/flags/default/ff2792c9a8e43eceee439755feca454e5049d676 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/Video.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/Video.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE)  -g -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/Video.o.d" -o ${OBJECTDIR}/_ext/1472/Video.o ../Video.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
${OBJECTDIR}/_ext/1472/vt100.o: ../vt100.c  .generated_files/flags/default/342675baa3c4be2bc89f5f0ea9f8616c4fcee1a2 .generated_files/flags/default/da39a3ee5e6b4b0d3255bfef95601890afd80709
	@${MKDIR} "${OBJECTDIR}/_ext/1472" 
	@${RM} ${OBJECTDIR}/_ext/1472/vt100.o.d 
	@${RM} ${OBJECTDIR}/_ext/1472/vt100.o 
	${MP_CC}  $(MP_EXTRA_CC_PRE)  -g -x c -c -mprocessor=$(MP_PROCESSOR_OPTION)  -fno-common -MP -MMD -MF "${OBJECTDIR}/_ext/1472/vt100.o.d" -o ${OBJECTDIR}/_ext/1472/vt100.o ../vt100.c    -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)    
	
endif

# ------------------------------------------------------------------------------------
# Rules for buildStep: compileCPP
ifeq ($(TYPE_IMAGE), DEBUG_RUN)
else
endif

# ------------------------------------------------------------------------------------
# Rules for buildStep: link
ifeq ($(TYPE_IMAGE), DEBUG_RUN)
${DISTDIR}/Terminal.${IMAGE_TYPE}.${OUTPUT_SUFFIX}: ${OBJECTFILES}  nbproject/Makefile-${CND_CONF}.mk    ../Linker\ Script/32MX250F128B.ld
	@${MKDIR} ${DISTDIR} 
	${MP_CC} $(MP_EXTRA_LD_PRE) -g   -mprocessor=$(MP_PROCESSOR_OPTION)  -O1 -o ${DISTDIR}/Terminal.${IMAGE_TYPE}.${OUTPUT_SUFFIX} ${OBJECTFILES_QUOTED_IF_SPACED}          -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)      -Wl,--defsym=__MPLAB_BUILD=1$(MP_EXTRA_LD_POST)$(MP_LINKER_FILE_OPTION),--defsym=__MPLAB_DEBUG=1,--defsym=__DEBUG=1,-D=__DEBUG_D,--defsym=_min_heap_size=0,--defsym=_min_stack_size=1024,--memorysummary,${DISTDIR}/memoryfile.xml,-G4 
	
else
${DISTDIR}/Terminal.${IMAGE_TYPE}.${OUTPUT_SUFFIX}: ${OBJECTFILES}  nbproject/Makefile-${CND_CONF}.mk   ../Linker\ Script/32MX250F128B.ld
	@${MKDIR} ${DISTDIR} 
	${MP_CC} $(MP_EXTRA_LD_PRE)  -mprocessor=$(MP_PROCESSOR_OPTION)  -O1 -o ${DISTDIR}/Terminal.${IMAGE_TYPE}.${DEBUGGABLE_SUFFIX} ${OBJECTFILES_QUOTED_IF_SPACED}          -DXPRJ_default=$(CND_CONF)    $(COMPARISON_BUILD)  -Wl,--defsym=__MPLAB_BUILD=1$(MP_EXTRA_LD_POST)$(MP_LINKER_FILE_OPTION),--defsym=_min_heap_size=0,--defsym=_min_stack_size=1024,--memorysummary,${DISTDIR}/memoryfile.xml,-G4 
	${MP_CC_DIR}\\xc32-bin2hex ${DISTDIR}/Terminal.${IMAGE_TYPE}.${DEBUGGABLE_SUFFIX} 
endif


# Subprojects
.build-subprojects:


# Subprojects
.clean-subprojects:

# Clean Targets
.clean-conf: ${CLEAN_SUBPROJECTS}
	${RM} -r ${OBJECTDIR}
	${RM} -r ${DISTDIR}

# Enable dependency checking
.dep.inc: .depcheck-impl

DEPFILES=$(wildcard ${POSSIBLE_DEPFILES})
ifneq (${DEPFILES},)
include ${DEPFILES}
endif
