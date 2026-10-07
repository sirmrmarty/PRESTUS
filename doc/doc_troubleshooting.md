# Troubleshooting

This document contains fixes to known usage issues. If you find and solve an issue not listed here, please add it with an elaborate explanation. If you stumble upon an error in the working of the pipeline, or have suggestions for improvement, please [open an issue on GitHub](https://github.com/Donders-Institute/PRESTUS/issues).

## Simulation errors
- An error occurs where the script can't find the `makeBowl.m` function.
    - This means that the path to k-Wave has not been defined properly.

## HPC / scratch errors
See [doc_hpc.md](doc_hpc.md#node-local-scratch) for how node-local scratch works.
- The job log warns `no scratch directory was found ... using shared storage`.
    - None of the scratch locations existed. PRESTUS creates `/scratch/$USER/$SLURM_JOB_NAME` itself, but only when `/scratch/$USER` exists. Set `hpc.scratch_dir` explicitly in your config (e.g. `'/scratch/${USER}/${SLURM_JOB_NAME}'`); it is created if missing. If your cluster uses another base than `/scratch`, set `$PRESTUS_SCRATCH_BASE` instead. Alternatively, turn scratch off with `hpc.tmp_gb: 0`.
- A SLURM job stays pending after scratch was enabled.
    - No node can provide `--tmp=<tmp_gb>G`. Lower `hpc.tmp_gb`, or set it to `0`.
- A later run cannot find cached acoustic, grid or medium results (e.g. with `run_acoustic_sims: 0` or `overwrite_files: 'never'`).
    - The run that produced them kept `cache/` on scratch, and the cache was discarded at the end of that job. Re-run it with `hpc.scratch_cache: 0` (or `simulation.debug: 1`) so the cache stays in `<output>/cache/`.

## Segmentation errors
- When SimNIBS has not yet run the segmentation (found in the m2m folder), the pipeline will only run the segmentation.
    - Only after segmentation has been completed can the pipeline be restarted to run the acoustic simulation.
- When running bilateral simulations simultaneously when segmentation has not yet been completed, both will try to start a segmentation run.
    - One of these will produce an `segment_error` file in the `batch_job_logs` folder. Simply wait for the segmentation to complete and run both again.
- A common segmentation error is `ValueError: The qform and sform of do not match. Please run charm with the --forceqform option`. 
    - This can be solved by adding `segmentation.use_qform: 1` to your config file.
