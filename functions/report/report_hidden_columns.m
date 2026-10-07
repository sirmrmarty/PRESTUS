function cols = report_hidden_columns()
% REPORT_HIDDEN_COLUMNS  Per-subject CSV columns that HTML reports never show
%
% acoustic_analysis still writes these to the CSV, but the reports drop them
% everywhere (tables, dashboards, JSON payloads): the ITRUSST mechanical
% criterion is the transcranial MI (MI_tc), so skull / skin MI only add noise
% to the safety view.
%
% Use as:
%   cols = report_hidden_columns()
%
% Output:
%   cols - cell array of CSV column names to drop before rendering
%
% See also: GENERATE_SIMULATION_REPORT, GENERATE_GROUP_REPORT, GET_RISK_LIMITS

    cols = {'MI_skull', 'MI_skin'};
end
