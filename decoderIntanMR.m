function decoderIntanMR(filename)
% DECODERINTAN reads digital data from the function generator (via Intan), and separates out binary
% parameter information and stimulation envelopes.  Output is a file called 'ExtractedData.mat' that
% contains a structure called 'trials', which contains information for each trial found in the digital
% channel data.  Information within variable 'trials':
%
%           BitData| sub-structure containing information for each bit in the corresponding trial:
%                  ||   bitMean: average value of the bit information
%                  ||  bitValue: whether it's a 1 or 0.  Based on thresholding bitMean at 0.95
%                  ||  bitStart: start of the bit information within the digital data
%                  ||    bitEnd: end of the bit information within the digital data
%                  ||    bitEnv: digital channel information in the bit
%          trialEnv| trial information in the digital data
%           stimEnv| stimulation envelope, within the trial data
%        trialStart| start of the trial phase, reference to start of digital data
%          trialEnd| end of the trial phase, reference to start of digital data
%         stimStart| start of the stimulation, reference to the start of the digital data
%           stimEnd| end of the stimulation, reference to the start of the digital data
%       carrierFreq| decoded carrier frequency for the trial [kHz]
%         amplitude| decoded amplitude for the trial (input to fxn generator) [mV]
%         dutyCycle| decoded duty cycle for the trial [%]
%           modFreq| decoded modulating frequency for the trial [Hz]
%     pulseDuration| decoded pulse duration for the trial [ms]
%
% Errors should not cause the code to quit, but should instead place empty values in the location
% of the error.

%% Initializations // File Loading
if ~exist('nParams','var')
    nParams = 3; % default to 3 parameters
end

addpath(cd);
addpath(pwd);

if ~exist('filename','var')
    [dataName,trialsName,~,rawDataName] = MatNames;
elseif isempty(filename)
    [dataName,trialsName,~,rawDataName] = MatNames;
else
    dataName     = [           filename(1:end-4),'_Digital.mat'  ];
    trialsName   = ['trials_', filename(1:end-4),'.mat'];
    rawDataName  = [           filename(1:end-4),'.mat'];
end


try load(dataName,'*dig*','*adc*','ana*','freq*','v*'); % load in all variables with these
catch
    try load(rawDataName,'*dig*','freq*','v*');
    catch
        error('Must run conversion scripts: convert_rhs.m or convert_dat.m');
    end
end
try data(:,1) = board_dig_in_data(:,2);   % load from .rhs file
    data(:,2) = board_dig_in_data(:,1);
catch
    try data = digital_data';        % load from .dat file
    catch
        try data(1,:) = v';
        catch
            error('Check input data for variable name.');
        end
    end
    
end % try to load variables of different names

% if ~iscolumn(data)
%     data = data';
% end
fs = frequency_parameters.board_dig_in_sample_rate; % get sampling frequency from data

ii = 2; % start at 2nd time point

[startBuzz(1),endBuzz(1),new_ii] = findBuzz(data,2); % find the first buzz

ii=new_ii;

% initialize export structure
trials = struct(...
    'bitData',          struct(...
    'bitMean',      [],...
    'bitValue',     [],...
    'bitStart',     [],...
    'bitEnd',       [],...
    'bitEnv',       []...
    )...
    );

%% MAIN LOOP
% Goes through the entire digital data, finding buzzes and decoding what's in-between
iBit = 0; iTrial = 1;
while ii<length(data) % loop through digitalData
    disp(['Trial #',num2str(iTrial),', Bit ',num2str(iBit)]);
    % find the next buzz
    [startBuzz(2),endBuzz(2),new_ii] = findBuzz(data,ii); % Call findBuzz
    % inter-buzz duration
    lbetweenBuzz = startBuzz(2)-endBuzz(1);
    bit = lbetweenBuzz < fs/2; % bit information is always less than 0.5 seconds
    
    switch bit
        case 1 % treat data as a bit
            %% BIT DATA
            iBit = iBit + 1; % go to next bit
            bitstream = data(endBuzz(1):startBuzz(2)); % stream of bit
            bitMean = mean(bitstream); % average value of the bit data
            bitValue = bitMean > 0.95; % separates 0s from 1s with threshold of 0.95
            trials(iTrial).bitData(iBit).bitMean    = bitMean;
            trials(iTrial).bitData(iBit).bitValue   = bitValue;
            trials(iTrial).bitData(iBit).bitStart   = endBuzz  (1);
            trials(iTrial).bitData(iBit).bitEnd     = startBuzz(2);
            trials(iTrial).bitData(iBit).bitEnv     = data(endBuzz(1):startBuzz(2));
            a = 1;
        case 0 % treat data as a trial
            %% TRIAL DATA
            %% Trial Event markers
            tic;
            trial_remove = 100;
            trialStart   = endBuzz  (1)+trial_remove;
            trialEnd     = startBuzz(2)-trial_remove;
            
            try trialstream = data(trialStart:trialEnd,2);
            catch
                trialstream = data(trialStart:end,2);
            end
            
            %             try trialstream = data(trialStart:trialEnd,2); % trial stream, remove 100 points from either end
            %             catch
            %                 trialstream = data(trialStart:end,2);
            %             end
            
            trials(iTrial).trialStart       = trialStart;  % start of trial phase
            trials(iTrial).trialEnd         = trialEnd  ;  % end of trial phase
            trials(iTrial).trialEnv     	= trialstream;   % entire trial phase
            a = 1;
            
            %% Stimulation Events markers
            stimStart   = find(trialstream,1,'first'); % referenced to start of trial
            stimEnd     = find(trialstream,1,'last' ); % referenced to start of trial
            
            try data(stimStart + trialStart);     % check if this value is within the digital signal
                data(stimEnd   + trialStart);
                
                % stimulation markers
                trials(iTrial).stimStart   	= stimStart + trialStart ; % referenced to start of session
                trials(iTrial).stimEnd     	= stimEnd   + trialStart ; % referenced to start of session
                trials(iTrial).stimEnv      = trialstream(stimStart:stimEnd);
                trials(iTrial).stimDur      = 1000*(trials(iTrial).stimEnd - trials(iTrial).stimStart)./fs;
                
            catch % replace with empty values if an error occurred in finding stim onset/offset
                trials(iTrial).stimStart  	= []; % start of stimulation
                trials(iTrial).stimEnd    	= []; % end of stimulation
                trials(iTrial).stimEnv      = []; %
            end
            
            %% Decoded Stimulation Parameters
            %try
            trialByte        = [trials(iTrial).bitData(:).bitValue]; % try to get the information
            trial_parameters = debinarize(trialByte,2);
            trials(iTrial).parameters_values  = trial_parameters;
            
            %catch % unable to extract parameters, set to empty, find corresponding trial in ParameterOrder.mat
            
            
            %end
            
            %fullTrials{iTrial,1} = data(trials(iTrial).bitData(1).bitStart:trials(iTrial).trialEnd);
            iBit = 0; % reset bit counter
            iTrial = iTrial + 1; % increment trial counter
    end
    
    %% NEXT TRIAL BUZZ SHIFT
    % shift 2nd buzz to first position
    startBuzz(1) = startBuzz(2);
    endBuzz  (1) = endBuzz  (2);
    
    ii=new_ii; % start looking where you left off
    
end

%% SAVE TO FILE // MOVE TO WORKSPACE
% save to file, in same folder as data
save(trialsName,'trials','rawDataName','fs');

% ParameterOrderDecoded = [...
%     [trials(:).carrierFreq]',...
%     [trials(:).amplitude]',...
%     [trials(:).dutyCycle]',...
%     [trials(:).modFreq]',...
%     [trials(:).pulseDuration]'];
%
try
disp(['       Number of Trials: ',num2str(length(trials))]);
disp(['Number of Unique Trials: ',num2str(length(unique(reshape([trials(:).parameters_values],2,[])','rows')))]);
catch disp('Unable to display trial count and unique trials count.');
end
% MOVE SELECT VARIABLES TO WORKSPACE
assignin('base','trials',               eval('trials'));
assignin('base','fs',                   eval('fs'));
%assignin('base','ParameterOrderDecoded',eval('ParameterOrderDecoded'));
%assignin('base','fullTrials',           eval('fullTrials'));
assignin('base','data',                 eval('data'));

end


%% ~~~~~~~~~~ ACCESSORY FUNCTIONS ~~~~~~~~~~~
% ~~~~~~~~~~~~~~~~~~~~~~~~~ FindBuzz ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function [buzzStart,buzzEnd,new_ii] = findBuzz(d1,startindex)
% FINDBUZZ finds the next buzz in the digital channel.  Inputs are the full digital channel data, and the
% starting index to find the next buzz.  Outputs are the start of the buzz, the end of the buzz, and the
% new starting index for the next iteration.  If the loop goes to the end of the digital channel without
% finding a buzz, a "phantom" buzz is returned, where the start and end of the buzz are both at the last
% point in the digital data.
%
% The algorithm to find the buzz uses a 10 data point window, and slides it along the digital data.  As
% it slides along the data until it finds where there are equal number of 1s and 0s, as well as more than
% 1 positive and negative changes, meaning there are fast oscillations occuring.  Once it finds the first
% point that this occurs (the start of the buzz), it continues until the sliding window shows only all 1s
% or 0s.  This algorithm can be sped up by increasing the size of the window, or by changing how fast the
% window slides along the data, but at a possible cost of decreased robustness and accuracy.

buzzStart   = length(d1);   % returns last point in digital data if not found in algorithm
buzzEnd     = length(d1);
new_ii      = length(d1);   % returns the end of the digital data if this is not found in the algorithm
ii          = startindex;   % start while loop at startindex

inbuzzflag = 0;         % initialize inbuzz to 0 (not in a buzz)

while ii < length(d1)-10
    win = ii:ii+9; % scanning window to find a Buzz
    
    nZeros          = sum(d1(win) == 0);         	% number of zeros in window
    nOnes           = sum(d1(win) == 1);         	% number of ones in window
    nPosChanges     = sum(diff(d1(win)) == 1);      % number of positive changes in window
    nNegChanges     = sum(diff(d1(win)) == -1);     % number of negative changes in window
    
    if abs(nZeros-nOnes) <= 1 % if the number of ones and zeros are close to each other, it's oscillating
        if nPosChanges > 1 && nNegChanges > 1 % if it is acutally oscillating, both of these numbers will be greater than 1
            if ~inbuzzflag % not in a buzz already
                buzzStart = win(1); % start of buzz at first detection of oscillation
            end
            inbuzzflag = 1; % we know we're in a buzz, change behavior
            
        else% no need to do anything here
        end
        
    elseif abs(nZeros-nOnes) == length(win) % stopped oscillation, steadily 0 or 1
        if inbuzzflag==1 % only if currently in a buzz, break out of loop
            buzzEnd = win(1);
            new_ii  = win(end);
            break; % exit while loop
        end
    else% error catching should go in here, works well without anything here so far
    end
    
    ii=ii+1;
    
    if ii >= length(d1)-10 % goes to end of data, didn't find one at all
        buzzStart   = length(d1); % set to end
        buzzEnd     = length(d1); % set to end
        new_ii      = length(d1); % set to end
    end
end
end


% ~~~~~~~~~~~~~~~~~~~~~~~ debinarize ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function ParaOut = debinarize(dataBlock,nParams)
% DEBINARIZE converts from binary to base-10.  Requires a 2^n byte size (8, 16, 32, etc).
bytesize = floor((length(dataBlock)-1)/2);

N = size(dataBlock,2);
%[,N] = size(dataBlock); % get size of dataBlock

%bytesize = floor(N/nParams);   % byte-size the divisor of number of columns and number of params
bytesize = [length(dataBlock)-2,2];

ParaOut(1) = bin2dec(num2str(dataBlock(1:bytesize(1))));
ParaOut(2) = bin2dec(num2str(dataBlock(bytesize(1)+1:bytesize(1)+bytesize(2))));

%nParams = 2;
% ParaOut = zeros(1,nParams); % initialize
% for j = 1:nParams % Parameter
%     for b = 1:bytesize(j) % Bit (Goes from MSB to LSB)
%         ParaOut(1,j) = 2*ParaOut(1,j); % Bitshift
%         ParaOut(1,j) = ParaOut(1,j)+dataBlock(1,bytesize(j)*j-bytesize(j)+b); % Add next bit
%     end
% end

end