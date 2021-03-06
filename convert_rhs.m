clearvars -except FG*;

[file, path, filterindex] = ...
    uigetfile('*.rhs', 'Select an RHS2000 Data File', 'MultiSelect', 'on');

if ~iscell(file)
    file = {file};
end
cd(path);
for ii=1:length(file)
    clearvars -except filename file path ii
    filename = [path,file{ii}];
    disp(filename);
    read_Intan_RHS2000_file(filename);
    
    a = whos;
    b = {a.name};
    if exist('amplifier_data','var')
        amplifier_data          = amplifier_data';
        charge_recovery_data    = charge_recovery_data';
        amp_settle_data         = amp_settle_data';
        compliance_limit_data   = compliance_limit_data';
        stim_data               = stim_data';
    end
    
    if exist('board_dig_in_data','var')
        board_dig_in_data = board_dig_in_data';
    end
    try save([filename(1:end-4),'_Amplifier'],  'amp*','freq*','notes','-v7.3');
    catch; end
    try save([filename(1:end-4),'_Stim'],  'charge*','compliance*','spike*','stim*','freq*','notes','-v7.3');
    catch; end
    try save([filename(1:end-4),'_Digital'],    '*dig*','freq*','notes','-v7.3');
    catch; end
    try save([filename(1:end-4),'_Analog'],     '*adc*','freq*','notes','-v7.3');
    catch; end
    %save(filename(1:end-4),b{:});
end