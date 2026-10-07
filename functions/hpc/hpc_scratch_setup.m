function [parameters, cleanup] = hpc_scratch_setup(parameters, options)
% HPC_SCRATCH_SETUP  Redirect k-Wave .h5 files (and optionally cache/) to node-local scratch
%
% When hpc.tmp_gb > 0 (default 50) and MATLAB runs inside a SLURM job
% (SLURM_JOB_ID set), creates a job-specific working directory on node-local
% scratch and points io.dir_scratch at it. The C++ k-Wave codes (cpp_cpu,
% cpp_gpu) write their input/output .h5 files there instead of to
% <output>/cache on shared storage.
%
% With hpc.scratch_cache = 1 (default), io.dir_cache is also moved to
% <scratch>/cache. That cache is discarded when the pipeline finishes.
% Debug runs (simulation.debug = 1) keep the shared cache so it survives
% crashes; sequential runs (options.sequential_configs /
% options.is_sequential_run) keep it because follow-up runs read it.
%
% Outside a SLURM job (local MATLAB, qsub), or with hpc.tmp_gb = 0,
% parameters are returned unchanged.
%
% Use as:
%   [parameters, cleanup] = hpc_scratch_setup(parameters, options)
%
% Input:
%   parameters - PRESTUS config after path_log_setup; relevant fields:
%                  .hpc.tmp_gb, .hpc.scratch_dir, .hpc.scratch_cache,
%                  .io.dir_cache, .io.output_affix, .simulation.debug
%   options    - prestus_pipeline options struct (optional)
%
% Output:
%   parameters - io.dir_scratch set; io.dir_cache redirected to scratch and
%                io.dir_cache_shared set when the cache is on scratch
%   cleanup    - onCleanup object that calls hpc_scratch_finalize when it is
%                destroyed; [] when scratch is inactive or the directory was
%                created by an outer (nested) pipeline call that owns it
%
% See also: HPC_SCRATCH_FINALIZE, HPC_SUBMIT_JOB, PATH_LOG_SETUP

arguments
    parameters (1,1) struct
    options    (1,1) struct = struct()
end

cleanup = [];

if ~isfield(parameters, 'hpc') || ~isfield(parameters.hpc, 'tmp_gb') || ...
        isempty(parameters.hpc.tmp_gb) || parameters.hpc.tmp_gb <= 0
    return
end

% Only inside a SLURM job (the only scheduler that gets --tmp); local and
% qsub runs keep the shared paths
job_id = getenv('SLURM_JOB_ID');
if isempty(job_id), return; end
job_id = regexprep(job_id, '[^\w.-]', '_');

[root, created_root] = resolve_scratch_root(parameters);
if isempty(root)
    warning('prestus:scratch', ['hpc.tmp_gb = %g but no scratch directory was found ' ...
        '(hpc.scratch_dir, $PRESTUS_SCRATCH, $SLURM_TMPDIR, /scratch/$USER/$SLURM_JOB_NAME, $TMPDIR); ' ...
        'using shared storage.'], ...
        parameters.hpc.tmp_gb);
    return
end
if ~isempty(created_root)
    fprintf('Created per-job scratch folder: %s\n', created_root);
end

affix = '';
if isfield(parameters, 'io') && isfield(parameters.io, 'output_affix')
    affix = char(parameters.io.output_affix);
end
scratch_dir = fullfile(root, sprintf('prestus_%s', job_id), ...
    sprintf('sub-%03d%s', parameters.subject_id, affix));

% A nested pipeline call in the same job reuses the directory but does not
% own it, so it never deletes it from under the outer run.
owns_dir = ~isfolder(scratch_dir);
if owns_dir
    [ok, msg] = mkdir(scratch_dir);
    if ~ok
        warning('prestus:scratch', 'Could not create scratch directory %s (%s); using shared storage.', ...
            scratch_dir, msg);
        if ~isempty(created_root), [~, ~] = rmdir(created_root, 's'); end
        return
    end
end
parameters.io.dir_scratch = scratch_dir;

fprintf('Node-local scratch: %s', scratch_dir);
free_gb = scratch_free_gb(scratch_dir);
if ~isnan(free_gb)
    fprintf(' (%.1f GB free, %g GB requested)', free_gb, parameters.hpc.tmp_gb);
end
fprintf('\n');
if free_gb < parameters.hpc.tmp_gb
    warning('prestus:scratch', 'Only %.1f GB free on scratch, less than hpc.tmp_gb = %g GB.', ...
        free_gb, parameters.hpc.tmp_gb);
end

% Cache on scratch (discarded at the end). Debug runs and sequential runs
% keep it on shared storage: debug so it survives crashes for inspection,
% sequential because follow-up runs read it.
scratch_cache = ~isfield(parameters.hpc, 'scratch_cache') || parameters.hpc.scratch_cache;
is_sequential = isfield(options, 'sequential_configs') || ...
    (isfield(options, 'is_sequential_run') && options.is_sequential_run);
is_debug = isfield(parameters, 'simulation') && isfield(parameters.simulation, 'debug') && ...
    parameters.simulation.debug == 1;

if scratch_cache && isfield(parameters.io, 'dir_cache') && ~isempty(parameters.io.dir_cache)
    if is_debug
        fprintf('Debug mode: cache stays on shared storage (%s)\n', parameters.io.dir_cache);
    elseif is_sequential
        fprintf('Sequential run: cache stays on shared storage (%s)\n', parameters.io.dir_cache);
    else
        cache_dir = fullfile(scratch_dir, 'cache');
        if ~isfolder(cache_dir), mkdir(cache_dir); end
        parameters.io.dir_cache_shared = parameters.io.dir_cache;
        parameters.io.dir_cache = cache_dir;
        fprintf('Cache on scratch: %s (discarded at the end)\n', cache_dir);
    end
end

if owns_dir
    cleanup = onCleanup(@() hpc_scratch_finalize(scratch_dir, created_root));
end

end

% ========== LOCAL FUNCTIONS ==========
function [root, created] = resolve_scratch_root(parameters)
% Explicit hpc.scratch_dir (env vars expanded, created if missing). Otherwise
% the first existing of $PRESTUS_SCRATCH, $SLURM_TMPDIR,
% <base>/$USER/$SLURM_JOB_NAME, <base>/$USER/$SLURM_JOB_ID. If none exists
% but <base>/$USER does, <base>/$USER/$SLURM_JOB_NAME is created (and
% returned as 'created' so it is removed again at the end). Last resort:
% $TMPDIR. <base> is $PRESTUS_SCRATCH_BASE, default /scratch.
    root = '';
    created = '';
    spec = 'auto';
    if isfield(parameters.hpc, 'scratch_dir') && ~isempty(parameters.hpc.scratch_dir)
        spec = strtrim(char(parameters.hpc.scratch_dir));
    end

    if strcmpi(spec, 'auto')
        base = getenv('PRESTUS_SCRATCH_BASE');
        if isempty(base), base = '/scratch'; end
        user_dir = fullfile(base, '$USER');
        job_dir  = fullfile(user_dir, '$SLURM_JOB_NAME');

        for c = {'$PRESTUS_SCRATCH', '$SLURM_TMPDIR', job_dir, fullfile(user_dir, '$SLURM_JOB_ID')}
            cand = expand_env(c{1});
            if ~isempty(cand) && isfolder(cand)
                root = cand;
                return
            end
        end

        % Per-job folder not there yet: create it under the user's scratch
        cand = expand_env(job_dir);
        if ~isempty(cand) && isfolder(expand_env(user_dir)) && mkdir(cand)
            root = cand;
            created = cand;
            return
        end

        cand = expand_env('$TMPDIR');
        if ~isempty(cand) && isfolder(cand)
            root = cand;
        end
    else
        cand = expand_env(spec);
        if isempty(cand) || (~isfolder(cand) && ~mkdir(cand))
            return
        end
        root = cand;
    end
end

function s = expand_env(s)
% Expand $VAR / ${VAR}; '' if any referenced variable is unset, so a path
% like /scratch/$USER/$SLURM_JOB_NAME never collapses to /scratch/<user>/.
    vars = regexp(s, '\$\{?(\w+)\}?', 'tokens');
    for k = 1:numel(vars)
        if isempty(getenv(vars{k}{1}))
            s = '';
            return
        end
    end
    s = regexprep(s, '\$\{?(\w+)\}?', '${getenv($1)}');
end

function free_gb = scratch_free_gb(d)
% Free space in GB via df (POSIX only); NaN when unavailable.
    free_gb = NaN;
    if ~isunix, return; end
    try
        [st, out] = system(sprintf('df -Pk "%s" | tail -1', d));
        if st == 0
            tok = regexp(strtrim(out), '\s+', 'split');
            free_gb = str2double(tok{4}) / 1024^2;
        end
    catch
    end
end
