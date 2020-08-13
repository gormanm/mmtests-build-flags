MMTests has support for specifying alternative toolchains, per-test optimisations,
runtime flags and sysctls via an external repository of which this is one example.
The intent is to be able to experiment with peak tuning without necessarily having
to modify mmtests itself and invalidate old configurations.

At the time of writing, only a very limited number of tests within
MMTests have valid configurations. It's updated via the MMTests script
bin/update-build-flags.sh
