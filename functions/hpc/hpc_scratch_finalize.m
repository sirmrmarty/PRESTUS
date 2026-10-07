function hpc_scratch_finalize(scratch_dir, created_root)
% HPC_SCRATCH_FINALIZE  Remove the node-local scratch directory
%
% Called through the onCleanup object returned by hpc_scratch_setup, so it
% runs when prestus_pipeline returns or errors. Removes the scratch cache and
% any .h5 files k-Wave left behind after a failed run. Errors are reported as
% warnings so they never mask the pipeline's own error.
%
% Use as:
%   hpc_scratch_finalize(scratch_dir)
%   hpc_scratch_finalize(scratch_dir, created_root)
%
% Input:
%   scratch_dir  - job-specific scratch directory (io.dir_scratch)
%   created_root - per-job scratch root that hpc_scratch_setup created
%                  (e.g. /scratch/$USER/$SLURM_JOB_NAME); removed only if it
%                  is empty afterwards. '' or omitted = leave the root alone.
%
% See also: HPC_SCRATCH_SETUP

if nargin < 2, created_root = ''; end

try
    if isfolder(scratch_dir)
        rmdir(scratch_dir, 's');
        fprintf('Removed node-local scratch: %s\n', scratch_dir);
    end
    [~, ~] = rmdir(fileparts(scratch_dir));   % prestus_<jobid> folder, only if now empty
    if ~isempty(created_root)
        [~, ~] = rmdir(created_root);         % per-job root we created, only if now empty
    end
catch ME
    warning('prestus:scratch', 'Could not remove scratch directory %s: %s', scratch_dir, ME.message);
end

end
