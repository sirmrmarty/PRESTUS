function convert_final_to_MNI_simnibs(path_to_input_img, m2m_folder, path_to_output_img, parameters, options)

% CONVERT_FINAL_TO_MNI_SIMNIBS Converts an image to MNI space using SimNIBS.
%
% This function uses the SimNIBS `subject2mni` command to transform an image 
% from subject-specific space to MNI space. It also removes unnecessary affixes 
% added by SimNIBS to the output filename.
%
% Input:
%   path_to_input_img  - String specifying the path to the input image in subject space.
%   m2m_folder         - String specifying the path to the `m2m` folder containing transformation data.
%   path_to_output_img - String specifying the desired path for the output image in MNI space.
%   parameters         - Struct containing pipeline configuration parameters:
%                        * simnibs_bin_path: Path to SimNIBS binaries.
%                        * ld_library_path: Optional path for library linking (if required).
%
% Options:
%   interpolation_order - Integer specifying the interpolation order for resampling (default: 1).
%
% Output:
%   The transformed image is saved at `path_to_output_img`.

    arguments
        path_to_input_img string
        m2m_folder string
        path_to_output_img string
        parameters struct
        options.interpolation_order = 1 % Default interpolation order
    end

    % Check if LD_LIBRARY_PATH is specified and construct the export command if needed
    if isfield(parameters, 'ld_library_path') && ~ispc
        ld_command = sprintf('export LD_LIBRARY_PATH="%s"; ', parameters.ld_library_path);
    else
        ld_command = ''; % No library linking required (or Windows)
    end

    % Build path separator for SimNIBS binary
    if ispc
        path_sep = '\';
    else
        path_sep = '/';
    end

    % Run SimNIBS `subject2mni` command to transform the image to MNI space
    if ispc
        % On Windows, activate the conda env first so MKL DLLs are on PATH
        env_dir = fileparts(parameters.simnibs_bin_path);        % .../simnibs_env
        envs_dir = fileparts(env_dir);                           % .../envs
        conda_base = fileparts(envs_dir);                        % .../conda
        activate_bat = fullfile(conda_base, 'condabin', 'activate.bat');
        [~, env_name] = fileparts(env_dir);
        if exist(activate_bat, 'file')
            cmd = sprintf('call "%s" %s && subject2mni --in "%s" --out "%s" --m2mpath "%s" --interpolation_order %d', ...
                activate_bat, env_name, path_to_input_img, path_to_output_img, m2m_folder, options.interpolation_order);
        else
            cmd = sprintf('"%s%ssubject2mni" --in "%s" --out "%s" --m2mpath "%s" --interpolation_order %d', ...
                parameters.simnibs_bin_path, path_sep, path_to_input_img, path_to_output_img, m2m_folder, options.interpolation_order);
        end
    else
        cmd = sprintf('%s"%s%ssubject2mni" --in "%s" --out "%s" --m2mpath "%s" --interpolation_order %d', ...
            ld_command, parameters.simnibs_bin_path, path_sep, path_to_input_img, path_to_output_img, m2m_folder, options.interpolation_order);
    end
    [status, result] = system(cmd);

    if status ~= 0
        warning('subject2mni failed (exit code %d). MNI conversion skipped.\nCommand: %s\nOutput: %s', ...
            status, cmd, result);
        return;
    end

    % Handle unnecessary affix added by SimNIBS to the output filename
    if ~matches(path_to_output_img, '_MNI.nii.gz')
        simnibs_name = strrep(path_to_output_img, '.nii.gz', '_MNI.nii.gz'); % Generate SimNIBS default filename
    else
        simnibs_name = path_to_output_img;
    end

    % Rename the file to match the desired output filename (cross-platform)
    if ~strcmp(simnibs_name, path_to_output_img) && exist(simnibs_name, 'file')
        movefile(simnibs_name, path_to_output_img);
    elseif ~exist(simnibs_name, 'file') && ~exist(path_to_output_img, 'file')
        warning('MNI output file not found: %s', simnibs_name);
    end
end
