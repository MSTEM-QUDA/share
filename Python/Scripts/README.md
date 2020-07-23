Python Scripts
==============

Collection of Python scripts to make using [SWMF](https://gitlab.umich.edu/swmf_software/SWMF) easier. Note most of these require a recent version of Python __3__. Supercomputers typically have this already.

Table of Contents:

- [prepare_geospace.py](#prepare_geospacepy)

prepare_geospace.py
-------------------

This script is to help with the inputs of the geospace model.

### Pre-steps

If you already have a run directory and `PARAM.in` file then skip ahead.

In the base directory of SWMF run:

```bash
SWMF$ ./Config.pl -install
# Compile then make the run directory if worked
SWMF$ make -j test_swpc_compile && make rundir
```
Make sure [swmfpy](https://gitlab.umich.edu/swmf_software/swmfpy) is installed:

```bash
# In the SWMF base dir
$ python3 -m pip install -U --user wheel  # Might be necessary
$ python3 -m pip install -U --user git+https://gitlab.umich.edu/swmf_software/swmfpy.git@master
```
*Note*: You may need to change `python3 -m pip` to `python -m pip` depending on your supercomputer's set up.

### Set up


Soft link the script into your run directory:

```bash
SWMF$ ln -s "$(realpath share/Python/Scripts/prepare_geospace.py)" run/
# The soft link is so that any updates automatically update this when you pull
```

Go to your run directory and copy a sensible `PARAM.in`:

```bash
SWMF$ cd run
SWMF/run$ cp Param/SWPC/PARAM.in_SWPC_v2_init PARAM.in
```

### Running

Then the final steps copy the script and the run directory into a work directory that your supercomputer allows before jobs:

```bash
SWMF$ cp run /some/work/dir/
SWMF$ cd /some/work/dir/
/some/work/dir$ python3 prepare_geospace.py --start_time 2014 2 3 4 5 6 --end_time 2014 3 4 5 6 7
# Your PARAM.in will be overwritten with those values
# Then submit job
```

### Options

To find out the options of `prepare_geospace.py` then run:

```bash
/some/work/dir$ ./prepare_geospace.py --help
# Help message output
```

Options can be useful to script this file with shell scripting, for example, when submitting jobs.