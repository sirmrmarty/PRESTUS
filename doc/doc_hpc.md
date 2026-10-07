### Usage on High-Performance Computing (HCP) setups

The Donders provides access to a high-performance computing (HPC) cluster. High-performance computing (HPC) clusters are systems composed of interconnected computers (nodes) working together to solve complex computational problems. They enable parallel processing, allowing large-scale simulations, data analysis, and scientific research tasks to be completed more efficiently. Each node typically consists of multiple processors (CPUs/GPUs), memory, and storage.

PRESTUS is designed for HPC deployment: the most efficient way to run simulations is to start multiple simulations (e..g, for different individuals, target locations, or parameter setups) via parallel jobs. **PBS** (Portable Batch System) and **SLURM** ((Simple Linux Utility for Resource Management)) are tools that manage job scheduling, resource allocation, and execution in HPC systems. Both tools ensure efficient usage of cluster resources by managing multiple users and workloads. The Donders manages both PBS (historically) and SLURM (more recent) schedulers. To see current ressource usage, see https://grafana.dccn.nl/ (*intranet required*).

The following sections describe workflows at the Donders to start (interactive) jobs.

For more extensive documentation, see the [HPC wiki](https://hpc.dccn.nl/) (*intranet required*).

<details markdown>
<summary>Donders HPC — PBS workflow</summary>

1. Select an access node: `mentat001`, `mentat002`, `mentat003`, `mentat004`

2. Login: `ssh abcxyz@mentat004.dccn.nl`

3. Start VNC manager: `vncmanager - 2`

4. Connect via VNC (see [here](https://intranet.donders.ru.nl/index.php?id=vnc00&no_cache=1&sword_list%5B%5D=VNC)) — TigerVNC: enter ip [e.g., `mentat004.dccn.nl:12`]

5. Load QSUB: `module load qsub`

6. Start interactive job:
```
qsub -I -l 'nodes=1:gpus=1,feature=cuda,walltime=05:00:00,mem=24gb,reqattr=cudacap>=5.0'
```

7. Start MATLAB:
```
module load matlab/R2022b
matlab
```
*Note*: PBS only supports CUDA 11.2, which is dropped starting in R2023 — see [this issue](https://github.com/Donders-Institute/PRESTUS/issues/50).

8. Use PRESTUS scripts ending in `*_qsub*`.
9. Check job status in terminal: `qstat`

</details>

<details markdown>
<summary>Donders HPC — SLURM workflow</summary>

1. Select an access node: `mentat005`, `mentat006`, `mentat007` (previously `mentat001s`)

2. Login: `ssh abcxyz@mentat001.dccn.nl`

3. Start VNC manager: `vncmanager - 2`

4. Connect via VNC (see [here](https://intranet.donders.ru.nl/index.php?id=vnc00&no_cache=1&sword_list%5B%5D=VNC)) — TigerVNC: enter ip [e.g., `mentat007.dccn.nl:12`]

5. Load SLURM: `module load slurm`

6. Start interactive job:
    - Without MATLAB GUI: `srun --mem=8gb --time=01:00:00 --x11 -p interactive --pty bash -i`
    - With MATLAB GUI: `srun --partition=gpu --gres=gpu:1 --mem=8G --time=01:00:00 --x11 --pty /bin/bash -i`

7. Start MATLAB:
```
module load matlab/R2024a
matlab
```
*Note*: SLURM supports CUDA 12.2 — recent MATLAB versions (up to R2024) should be supported; see [this issue](https://github.com/Donders-Institute/PRESTUS/issues/50).

8. Use PRESTUS scripts ending in `*_slurm*`.
9. Check job status: `squeue`. For PBS→SLURM command migration see [this documentation](https://hpc.dccn.nl/docs/cluster_howto/compute_slurm.html#migrating-from-torque-pbs-to-slurm).

</details>

### Node-local scratch

The C++ k-Wave codes (`cpp_cpu`, `cpp_gpu`) write an input and an output `.h5` file per simulation (often 5–15 GB together). The intermediate `.mat` files in `<output>/cache/` add up too. By default, every SLURM job keeps both on the compute node's local disk:

```yaml
hpc:
  tmp_gb: 50          # default: adds '#SBATCH --tmp=50G' to the job script; 0 = off
  scratch_cache: 1    # default: cache/ on scratch too; 0 = keep cache/ on shared storage
```

Nothing changes for local MATLAB runs, qsub jobs, or when `tmp_gb: 0`.

#### Where scratch lives

The scratch root is resolved as follows:

1. `hpc.scratch_dir`, if it is not `'auto'`. Env vars are expanded, e.g. `'/scratch/${USER}/${SLURM_JOB_NAME}'`, and the folder is created if missing.
2. Otherwise, the first existing folder of:
   - `$PRESTUS_SCRATCH`
   - `$SLURM_TMPDIR`
   - `/scratch/$USER/$SLURM_JOB_NAME`, the per-job folder at the Donders HPC
   - `/scratch/$USER/$SLURM_JOB_ID`
3. If none of these exists but `/scratch/$USER` does, PRESTUS **creates** `/scratch/$USER/$SLURM_JOB_NAME`. It removes that folder again at the end, but only if PRESTUS created it and it is empty. A folder that already existed is never removed.
4. Otherwise `$TMPDIR`.
5. If none of these is found, PRESTUS warns and falls back to shared storage.

On clusters that use a different base than `/scratch` (e.g. `/scratch-local`), set the environment variable `PRESTUS_SCRATCH_BASE` before MATLAB starts.

A path that references an unset variable is skipped; it never collapses to e.g. `/scratch/<user>/`.

Inside the root, PRESTUS works in `prestus_<jobid>/sub-NNN<affix>/`. The job name comes from `hpc_job_name` (`hpc.job_prefix` + subject, max 20 characters), and the job ID from `$SLURM_JOB_ID`. Example at the Donders HPC:

```
/scratch/marwim/PS_sub-001/              <- per-job folder (scratch root; created if missing)
└── prestus_123456/sub-001/              <- PRESTUS working folder, removed at the end
    ├── kwave_sub-001_input.h5
    ├── kwave_sub-001_output.h5
    └── cache/                           <- only with scratch_cache: 1 (and not in debug mode)
```

To see which root was used, look for `Node-local scratch:` in the job log (`log_hpc/sub-NNN_slurm_output_<jobid>.log`). The same line shows the free space. When PRESTUS created the per-job folder itself, the log also shows a `Created per-job scratch folder:` line.

The warning *"no scratch directory was found"* means neither `/scratch/$USER` nor any of the variables above existed. You can set a path explicitly in your study config; it is created if missing:

```yaml
hpc:
  scratch_dir: '/scratch/${USER}/${SLURM_JOB_NAME}'
```

#### Cache after the job / after a crash

The `.h5` files always use scratch. Where `cache/` goes, and whether it survives, depends on the mode:

| Mode | `cache/` location | Normal end | MATLAB error (bug, k-Wave failure) | Killed (walltime, `scancel`, OOM, node failure) |
|---|---|---|---|---|
| default (`hpc.scratch_cache: 1`) | scratch | deleted | deleted | left to the scheduler; not reachable, normally wiped |
| `simulation.debug: 1` | `<output>/cache/` | kept | kept | kept |
| `hpc.scratch_cache: 0` | `<output>/cache/` | kept | kept | kept |
| multi-stage pipelines¹ | `<output>/cache/` | kept | kept | kept |

¹ Uncertainty, multi-ISPPA, async multi-transducer, calibration, and sequential runs. Their stages read each other's cache, so `scratch_cache` is forced to `0`.

On a normal end or a MATLAB error, the scratch folder is removed. That includes any `.h5` files left behind by a failed k-Wave run. Everything outside `cache/` is always written to shared storage and survives any crash. That covers logs (`log/`, `log_hpc/` slurm output/error files) and any NIfTI, PNG or CSV written before the crash.

#### Notes

- Because the cache is discarded, a later job cannot reuse an earlier job's cache. This affects, for example, `run_acoustic_sims: 0` to load a previous acoustic result, or `overwrite_files: 'never'` to resume. For such workflows, set `hpc.scratch_cache: 0`.
- Size `tmp_gb` for one `.h5` input/output pair plus the cache, with headroom; 50 GB suits whole-head grids. If nodes cannot provide it, the job stays pending — lower it or set `0`.
- When the cache must survive a crash, use `simulation.debug: 1` or `hpc.scratch_cache: 0`.

### GPU support

TUS simulations are accelerated by GPUs, but requesting GPUs can lead to longer wait times as the current concurrent GPU limit per user is 4. To reduce wait times, it is possible to run acoustic simulations first (to confirm targeting) because these require less RAM) and then run thermal simulations with the final protocol. Avoid blanket simulations (e.g., circling through all participants with all permutations) especially for thermal simulations.

Given that PRESTUS is a MATLAB toolbox, it currently only supports *Nvidia GPUs*. When Nvidia GPUs are digitally partitioned, there appears to be an issue with identifying the assigned GPU in MATLAB R2024+. For SLURM jobs, MATLAB R2023b is currently deployed by default.

The following settings can be used to specify the HPC GPU setup.

| Field                           | Default | Explanation                  |
|-------------------------------|-------------|-----------------------------|
| parameters.hpc_gpu                   | "gpu:1"       | Specific GPUs could be requested here (e.g.,```"nvidia_a100-sxm4-40gb:1"```, but this is not recommended. ```scontrol show nodes \| egrep -o gres/gpu:.*=[0-9] \| egrep -o 'nvidia_.*=' \| sort \| uniq \| sed 's/=//'``` lists available GPU types.|
| parameters.hpc_partition                   | "gpu"       | The Donders HPC offers a ```gpu40g``` partition that should be used for the majority of thermal simulations.  It consists of nodes with GPU with vRAM > 40 GB.|
| parameters.hpc_reservation                   | ""       | By default do not use a reserved cue.|

<details markdown>
<summary>Benchmark data — Nvidia GPUs</summary>

These are potentially unrepresentative benchmarks run on a 256 × 216 × 192 mm grid, with minor variations depending on transducer placement.

**Acoustic Simulations**

| GPU | Memory Used | Duration | Notes |
|---|---|---|---|
| A100 80 GB | 12 GB | 14 mins | Slightly smaller grid size |
| A100 80 GB (partitioned 2×40 GB) | 12 GB | 25 mins | |
| A100 40 GB | 12 GB | 19 mins | |
| A16 16 GB | 12 GB | 145 mins | |
| P100 16 GB | 12 GB | 43 mins | Compiled, ~L40s |
| L40S 47 GB | 14 GB | 28 mins | Compiled |

**Heating Simulations**

| GPU | Memory Used | Duration | Notes |
|---|---|---|---|
| A100 80 GB | ?? GB | ~12 s/trial (400 trials: ~90 mins) | Slightly smaller grid size |
| A100 40 GB | ?? GB | ~17 s/trial (400 trials: ~115 mins) | |
| A16 16 GB | Out of RAM | ??? | |
| P100 16 GB | Out of RAM | ??? | |
| L40S 47 GB | ?? GB | ~4 s/trial (400 trials: ~45 mins) | |

</details>
