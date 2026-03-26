function [norm_profile_focus, max_intens] = extract_real_intensity_profile(...
    parameters,...
    available_foci_wrt_exit_plane, ...
    desired_focal_distance_ep, ...
    intens_data, ...
    equipment_name, ...
    dist_from_exit_plane)

    % Extracts or interpolates the intensity profile at a specific focal depth.
    %
    % Arguments:
    % - parameters
    %   parameters.calibration.skip_front_peak_mm: Distance to skip near-field peaks when finding the maximum intensity [mm].
    %   parameters.calibration.path_output_profiles: Directory path for saving results.
    % - available_foci_wrt_exit_plane: Array of available focal depths relative to the exit plane [mm].
    % - desired_focal_distance_ep: Desired focal depth relative to the exit plane [mm].
    % - intens_data: Matrix containing intensity profiles for different focal depths.
    % - equipment_name: Name of the equipment for labeling plots.
    % - dist_from_exit_plane: Distance vector from the transducer [mm].
    %
    % Returns:
    % - profile_focus: Extracted or interpolated intensity profile at the desired focal depth.
    % - max_intens: Maximum intensity in the profile beyond the specified skip distance.

    % Check if the exact focal depth is available
    col_index = find(available_foci_wrt_exit_plane == desired_focal_distance_ep);

    if isempty(col_index)
        % Perform linear interpolation if the exact focus is not available
        [~, closestIndex] = min(abs(available_foci_wrt_exit_plane - desired_focal_distance_ep));
        closest_foci_wrt_exit_plane = available_foci_wrt_exit_plane(closestIndex);

        % Determine neighboring focal depths for interpolation
        if closest_foci_wrt_exit_plane > desired_focal_distance_ep
            closestIndex2 = closestIndex; % Higher focus
            closestIndex1 = closestIndex2 - 1; % Lower focus
        else
            closestIndex1 = closestIndex; % Lower focus
            closestIndex2 = closestIndex1 + 1; % Higher focus
        end

        % Validate indices for interpolation boundaries
        if closestIndex1 < 1 || closestIndex2 > length(available_foci_wrt_exit_plane)
            error('Focus is outside the range of available axial profiles. Interpolation not possible.')
        end

        % Retrieve intensity profiles for the neighboring focal depths
        focus_wrt_exit_plane_1 = round(available_foci_wrt_exit_plane(closestIndex1), 2);
        focus_wrt_exit_plane_2 = round(available_foci_wrt_exit_plane(closestIndex2), 2);
        profile_1 = intens_data(:, closestIndex1)';
        profile_2 = intens_data(:, closestIndex2)';

        % Normalize profiles by aligning their peaks to 0 (max of profile 1 and profile 2)
        [~, idx1] = max(profile_1);
        [~, idx2] = max(profile_2);

        x1_norm = dist_from_exit_plane - dist_from_exit_plane(idx1); % Align peak of profile 1 to 0
        x2_norm = dist_from_exit_plane - dist_from_exit_plane(idx2); % Align peak of profile 2 to 0

        % Define normalized common x-array
        x_common_norm = linspace(min(min(x1_norm), min(x2_norm)), ...
                                 max(max(x1_norm), max(x2_norm)), length(dist_from_exit_plane));
     
        % Interpolate profiles in normalized space
        y1_interp_norm = interp1(x1_norm, profile_1, x_common_norm, 'spline', 'extrap');
        y2_interp_norm = interp1(x2_norm, profile_2, x_common_norm, 'spline', 'extrap');
        
        % Calculate weight (alpha) for interpolation based on the relative focal depths
        alpha = (desired_focal_distance_ep - focus_wrt_exit_plane_1) / ...
                (focus_wrt_exit_plane_2 - focus_wrt_exit_plane_1);

        % Interpolate the profiles with the weight alpha
        norm_profile_focus  = (1-alpha) * y1_interp_norm + alpha * y2_interp_norm;

        % Map blended profile back to original dist_from_exit_plane space.
        % The blended peak (at x_common_norm=0) must land at desired_focal_distance_ep.
        % Weighted-average of the two bracketing peak positions gives the
        % baseline mapping; the residual shift corrects for the fact that
        % the blended peak may not sit at the weighted-average position.
        [~, peak_idx_blended] = max(norm_profile_focus);
        blended_peak_in_norm  = x_common_norm(peak_idx_blended);          % peak offset in normalised coords
        baseline_offset       = (1-alpha) * dist_from_exit_plane(idx1) ... % weighted original peak positions
                              +    alpha  * dist_from_exit_plane(idx2);
        current_peak_pos      = blended_peak_in_norm + baseline_offset;    % where peak would land without correction
        shift                 = desired_focal_distance_ep - current_peak_pos; % correction to hit target
        x_final               = x_common_norm + baseline_offset + shift;

        profile_focus = interp1(x_final, norm_profile_focus, dist_from_exit_plane, 'spline', 0);
        norm_profile_focus = profile_focus(:);
        % Plot the profiles and the interpolated result
        figure;
        plot(dist_from_exit_plane, profile_1, '-x', 'DisplayName', ...
            ['Measurement 1, focus at ' num2str(focus_wrt_exit_plane_1)]);
        hold on;
        plot(dist_from_exit_plane, profile_2, '-x', 'DisplayName', ...
            ['Measurement 2, focus at ' num2str(focus_wrt_exit_plane_2)]);
        plot(dist_from_exit_plane, profile_focus, '-x', 'DisplayName', ...
            ['Interpolated, focus at ' num2str(desired_focal_distance_ep)]);
        legend;
        xlabel('Distance wrt exit plane [mm]');
        ylabel('Intensity [W/cm^2]');
        title('Interpolation Input and Results');
    
    else
        % Use the exact profile if the focus matches an available value
        norm_profile_focus = intens_data(:, col_index)';

        % Plot the exact profile
        figure;
        plot(dist_from_exit_plane, norm_profile_focus, '-o');
        xlabel('Distance wrt exit plane [mm]');
        ylabel('Intensity [W/cm^2]');
        title(['Axial Profile at Focus wrt Exit Plane: ' num2str(desired_focal_distance_ep) ' [mm]']);
    end
    % Create output profile if it does not yet exist
    if ~exist(parameters.calibration.path_output_profiles); mkdir(parameters.calibration.path_output_profiles); end
    % Save the plot to the specified directory
    fig_path = fullfile(parameters.calibration.path_output_profiles, ...
        strcat('Interpolation_at_F_', num2str(desired_focal_distance_ep), '_', equipment_name, '.png'));
    saveas(gcf, fig_path);
    close(gcf);

    % Determine the maximum intensity beyond the specified skip distance 
    % for scaling to prevent catching max peak in near field peak.
    [~, closestIndex] = min(abs(dist_from_exit_plane - parameters.calibration.skip_front_peak_mm));
    max_intens = max(norm_profile_focus(closestIndex:end));
    
end