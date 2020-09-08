#!/bin/bash

VERSION="hpc-v4r2"
MMTESTS_GIT_COMMIT="af2f189d851e0721ea7787491340c07765fc779f"
MONITORS="no-monitor run-monitor"
LOCAL_MIRROR=UNAVAILABLE
export MMTESTS_TOOLCHAIN="gcc-9"
export SOURCES_FLUSH="no"

# build-flags control
export BUILDFLAGS_ENABLE_COMPILEFLAGS=yes
export BUILDFLAGS_ENABLE_MPIFLAGS=no
export BUILDFLAGS_ENABLE_SYSCTL=no

rm -f /tmp/restore.sysctl
echo Backing up sysctl
for SYSCTL in kernel.numa_balancing; do
	sudo sysctl $SYSCTL | sed -e 's/ = /=/' | tee -a /tmp/restore.sysctl
done

CONFIG_LIST="
config-hpc-abinit-tmbt-hpcext-full
config-hpc-frontistr-hinge-hpcext-full
config-hpc-openfoam-motorbike-subdomains-hpcext-full
config-hpc-openfoam-motorbike-subdomains-large-hpcext-full-meshonly
config-hpc-salmon-classicem-omp-hpcext-full
config-hpc-specfem3d-small-s362ani-mpi-full
config-hpc-wrf-conus12km-hpcext-mpi-full
config-hpc-mpas-atmosphere-jwbaroclinic-full
config-hpc-mpas-atmosphere-supercell-full
"

if [ ! -e run-mmtests.sh ]; then
	echo Does not appear to be a mmtests installation
	exit -1
fi

restore_sysctl() {
	for SYSCTL in `cat /tmp/restore.sysctl`; do
		sudo sysctl $SYSCTL
	done
}
cleanup() {
	git checkout config
	git checkout shellpacks/common-config.sh
	restore_sysctl
}
trap cleanup EXIT

# Update mmtests and bring is to a known state
git remote update || exit -1
git checkout origin/master || exit -1
if [ "$MMTESTS_GIT_COMMIT" != "" ]; then
	if [ "$MMTESTS_GIT_COMMIT" != `git rev-parse origin/master` ]; then
		echo WARNING: MMTests commit does not match origin/master
		echo This may not be an issue but double check if it is intended.
		echo Optionally clear the MMTESTS_GIT_COMMIT at the start of
		echo the script
		sleep 5
		git checkout $MMTESTS_GIT_COMMIT || exit -1
	fi
fi
sed -i -e "s/mcp/$LOCAL_MIRROR/" shellpacks/common-config.sh
git clean -f configs &> /dev/null
./bin/autogen-configs
rm -rf work

# Update build-flags
./bin/update-build-flags.sh

HOST=`hostname`
for MONITOR in $MONITORS; do
	LOGNAME=
	if [ "$MONITOR" = "run-monitor" ]; then
		LOGNAME="-monitor"
	fi

	mkdir -p hpc-logs$LOGNAME
	for CONFIG in $CONFIG_LIST; do
		if [ -e /tmp/STOP ]; then
			echo Stopping
			rm /tmp/STOP
			exit
		fi
		if [ -e hpc-logs$LOGNAME/$CONFIG/$HOST$VERSION ]; then
			echo Skipping hpc-logs$LOGNAME/$CONFIG/$HOST$VERSION
			continue
		fi
		rm shellpacks/shellpack-*

		umount work/testdisk 2> /dev/null
		rm -rf work/log
		rm -rf work/testdisk
		rm -rf work/tmp
		if [ "$SOURCES_FLUSH" != "no" ]; then
			rm -rf work/sources-backup
			mkdir work/sources-backup
			mv `find work/sources -maxdepth 1 -type d -name open*` work/sources-backup/
			./bin/clean-sources
			mv work/sources-backup/* work/sources
			rmdir work/sources-backup/
		fi

		SAVE_TOOLCHAIN=$MMTESTS_TOOLCHAIN
		cp configs/$CONFIG config
		if [ $? -ne 0 ]; then
			echo Failed to copy configs/$CONFIG
			exit -1
		fi

		echo $CONFIG | grep -q abinit
		if [ $? -eq 0 ]; then
			echo "export ABINIT_PREPARE=yes" >> config
		fi

		echo Executing run-all $MONITOR $MMTESTS_TOOLCHAIN $CONFIG
		mkdir -p hpc-logs$LOGNAME/$CONFIG
		./run-mmtests.sh --$MONITOR $HOST$VERSION 2>&1 | tee hpc-logs$LOGNAME/$CONFIG/$HOST$VERSION.log
		RET=$?
		mkdir -p hpc-logs$LOGNAME/$CONFIG
		mv work/log/$HOST$VERSION hpc-logs$LOGNAME/$CONFIG/$HOST$VERSION
		echo $RET > hpc-logs$LOGNAME/$CONFIG/$HOST$VERSION/exit_status
		export MMTESTS_TOOLCHAIN=$SAVE_TOOLCHAIN
		restore_sysctl
	done
done
