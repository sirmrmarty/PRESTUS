function ok = safe_rmdir(d, n_tries, pause_s)
% SAFE_RMDIR  Best-effort recursive folder removal that never errors
%
% Like rmdir(d, 's'), but retries a few times. If the folder still cannot be
% removed, it deletes all files it can one by one (so e.g. large .mat files
% are gone even if one file is locked), removes the emptied subfolders, and
% warns about what is left. Meant for
% optional cleanup steps (e.g. removing a cache folder at the end of a run),
% where a failure must not crash a pipeline whose results are already saved.
% On network filesystems (NFS) a folder can briefly look non-empty after
% files were written by another node (.nfsXXXX files, stale listings);
% pausing between attempts lets it settle.
%
% Use as:
%   ok = safe_rmdir(d)
%   ok = safe_rmdir(d, n_tries, pause_s)
%
% Input:
%   d       - folder to remove (with all contents)
%   n_tries - number of attempts (default 3)
%   pause_s - seconds to wait between attempts (default 5)
%
% Output:
%   ok      - true if the folder is gone (or never existed); false if it
%             could not be removed completely, in which case a
%             'prestus:rmdir' warning lists the locked files that remain
%
% See also: RMDIR, HPC_SCRATCH_FINALIZE

arguments
    d       (1,:) char
    n_tries (1,1) double {mustBeInteger, mustBePositive} = 3
    pause_s (1,1) double {mustBeNonnegative} = 5
end

    ok = true;
    if ~isfolder(d), return; end

    msg = '';
    for k = 1:n_tries
        [ok, msg] = rmdir(d, 's');
        if ok || ~isfolder(d)
            ok = true;
            return
        end
        if k < n_tries, pause(pause_s); end
    end

    % Fallback: delete whatever can be deleted, file by file, so at most the
    % locked files (and the folders holding them) remain.
    files = dir(fullfile(d, '**', '*'));
    files = files(~[files.isdir]);
    ws = warning('off', 'MATLAB:DELETE:Permission');
    restore = onCleanup(@() warning(ws));
    for k = 1:numel(files)
        try
            delete(fullfile(files(k).folder, files(k).name));
        catch
        end
    end
    clear restore

    % Remove now-empty subfolders, deepest first, then the folder itself
    subdirs = dir(fullfile(d, '**'));
    subdirs = subdirs([subdirs.isdir] & ~ismember({subdirs.name}, {'.', '..'}));
    paths = fullfile({subdirs.folder}, {subdirs.name});
    [~, order] = sort(cellfun(@numel, paths), 'descend');
    for k = order
        [~, ~] = rmdir(paths{k});
    end
    [ok, ~] = rmdir(d);
    if ok, return; end

    left = dir(fullfile(d, '**', '*'));
    left = left(~[left.isdir]);
    names = strjoin({left(1:min(3, end)).name}, ', ');
    if numel(left) > 3, names = [names, ', ...']; end
    ok = false;
    msg = regexprep(strtrim(msg), '\s+', ' ');
    warning('prestus:rmdir', ['Could not remove %s (%s). Deleted what was possible; ' ...
        '%d locked file(s) left: %s'], d, msg, numel(left), names);
end
