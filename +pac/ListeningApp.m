classdef ListeningApp < handle
    %LISTENINGAPP Synchronized, level-matched A/B listening workbench.
    properties (SetAccess=private)
        Figure
        UI
        Data = {}
        Cursor = 0
        Active = 1
        IsPlaying = false
        Dirty = true
        Busy = false
        Gain = 1
        Player = []
        Root
    end
    properties (Access=private)
        SegmentStart = 0
        PlayToken = 0
        Duration = 10
        Marker
        Closing = false
    end
    methods
        function app=ListeningApp(root)
            app.Root=root; app.build(); app.refreshControls();
        end
        function loadComparison(app)
            if app.Busy, return; end
            app.stopPlayback(false); app.Busy=true; app.Dirty=true; app.refreshControls();
            app.UI.Status.Text='Loading comparison. Missing versions are encoded once and cached...';
            drawnow;
            try
                pair=cell(1,2);
                for side=1:2
                    cfg=app.selectedConfig(side);
                    pair{side}=pac.listening_variant(app.Root,app.UI.Source.Value,cfg, ...
                        strcmp(app.UI.Side(side).Kind.Value,'Original'));
                end
                app.Data=pair; app.Duration=numel(pair{1}.x)/pair{1}.fs;
                assert(numel(pair{1}.x)==numel(pair{2}.x),'pac:Input','Comparison lengths differ.');
                app.Cursor=0; app.UI.Start.Value=0; app.UI.Finish.Value=app.Duration;
                app.UI.Seek.Limits=[0 app.Duration]; app.UI.Seek.Value=0;
                app.Dirty=false;
                for side=1:2
                    d=pair{side};
                    if d.original
                        label='Original prepared audio | 48 kHz mono | 16-bit PCM reference: 768 kb/s';
                    else
                        if strcmp(d.rateMode,'vbr')
                            setting=sprintf('VBR, target %+g dB',d.config.vbr.distortionDB);
                        else
                            setting=sprintf('CBR, target %d kb/s',d.config.targetKbps);
                        end
                        [p,r]=pac.allocation_settings(d.config);
                        if p.enabled
                            if strcmp(d.rateMode,'vbr'), setting='VBR'; end
                            setting=sprintf('%s | piecewise limit %+g dB',setting,p.stopDB);
                        end
                        if r.enabled, setting=sprintf('%s | bucket',setting); end
                        label=sprintf('%s\n%s | actual %.2f kb/s | %.2f%% smaller | %d bytes', ...
                            strrep(d.model,'_',' '),setting,d.actualKbps,d.sizeReductionPercent,d.bytes);
                    end
                    app.UI.Side(side).Info.Text=label;
                end
                app.drawWaveform(); app.updateGain(); app.updatePosition();
                app.UI.Status.Text='Ready. Select A or B, then Play. Switching preserves the playback position.';
            catch exception
                app.UI.Status.Text=['Could not load: ' exception.message];
            end
            app.Busy=false; app.refreshControls();
        end
        function playPause(app)
            if app.Dirty || app.Busy, return; end
            if app.IsPlaying, app.stopPlayback(true); else, app.startPlayback(); end
        end
        function select(app,side)
            if app.Busy, return; end
            wasPlaying=app.IsPlaying; app.stopPlayback(true); app.Active=side;
            app.refreshControls();
            if wasPlaying && ~app.Dirty, app.startPlayback(); end
        end
        function stop(app)
            app.stopPlayback(false); app.Cursor=app.UI.Start.Value; app.updatePosition();
        end
        function seek(app,seconds)
            if app.Dirty || app.Busy, return; end
            wasPlaying=app.IsPlaying; app.stopPlayback(false);
            app.Cursor=max(app.UI.Start.Value,min(app.UI.Finish.Value,seconds));
            app.updatePosition(); if wasPlaying, app.startPlayback(); end
        end
        function saveNotes(app)
            if app.Dirty || app.Busy || isempty(app.Data), return; end
            folder=fullfile(app.Root,'outputs','listening','notes');
            if ~isfolder(folder), mkdir(folder); end
            record=struct('timeUTC',char(datetime('now','TimeZone','UTC', ...
                'Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z''')), ...
                'source',app.Data{1}.source,'heldOut',strcmp(app.Data{1}.source,'speech'), ...
                'startSeconds',app.UI.Start.Value,'endSeconds',app.UI.Finish.Value, ...
                'commonPlaybackGain',app.Gain,'activeSide',char('A'+app.Active-1), ...
                'notes',{app.UI.Notes.Value});
            record.A=rmfield(app.Data{1},{'x','fs'}); record.B=rmfield(app.Data{2},{'x','fs'});
            path=[tempname(folder) '.json']; pac.write_json(path,record);
            app.UI.Status.Text=['Saved listening notes: ' path];
        end
        function close(app)
            if app.Busy, return; end
            app.Closing=true; app.stopPlayback(false);
            if isfield(app.UI,'Dialog') && isgraphics(app.UI.Dialog.Figure), delete(app.UI.Dialog.Figure); end
            if isfield(app.UI,'ExperimentDialog') && isgraphics(app.UI.ExperimentDialog.Figure), delete(app.UI.ExperimentDialog.Figure); end
            if isgraphics(app.Figure), delete(app.Figure); end
        end
        function experimentControls(app,side)
            if app.Busy, return; end
            if isfield(app.UI,'ExperimentDialog') && isgraphics(app.UI.ExperimentDialog.Figure), delete(app.UI.ExperimentDialog.Figure); end
            e=app.UI.Side(side).Experiments;
            fig=uifigure('Name',['Codec experiments - ' char('A'+side-1)],'Theme','light', ...
                'Position',[180 90 690 580],'WindowStyle','modal');
            g=uigridlayout(fig,[10 1],'RowHeight',{54,145,32,32,32,32,32,'1x',28,32},'RowSpacing',6);
            uilabel(g,'Text','Supplementary experiments. For the assignment PAM-only comparison, leave all five OFF and use fixed bitrate with the original allocator. Variable windows change the required MDCT dimensions.', ...
                'WordWrap','on','FontColor',[.5 .2 .1]);
            box=uigridlayout(g,[5 1],'Padding',0,'RowHeight',{25,25,25,25,25},'RowSpacing',3);
            names={'zeroRun','fileHuffman','smartQuantizer','perceptualEntropy','variableWindows'};
            labels={'Zero-run coding','Per-file Huffman (automatic size fallback)', ...
                'Smarter quantizer search','Perceptual entropy: detection and allocation', ...
                'Variable MDCT windows (experimental; outside assignment dimensions)'};
            checks=gobjects(5,1);
            for k=1:5, checks(k)=uicheckbox(box,'Text',labels{k},'Value',e.(names{k})); end
            row=uigridlayout(g,[1 2],'ColumnWidth',{250,'1x'},'Padding',0);
            uilabel(row,'Text','Huffman book selection');
            scope=uidropdown(row,'Items',{'One per file','Per file + per-window books'},'ItemsData',{'file','window'},'Value',e.huffmanScope);
            keys={'stepRadius','peStrengthDB','attackProtectionDB','attackRatio'};
            labels={'Quantizer step search radius','PE precision boost (dB)','Attack protection (dB)','Energy jump ratio for attacks'};
            limits={[1 8],[0 12],[0 24],[2 100]}; numeric=gobjects(4,1);
            for k=1:4
                row=uigridlayout(g,[1 2],'ColumnWidth',{250,'1x'},'Padding',0);
                uilabel(row,'Text',labels{k}); numeric(k)=uieditfield(row,'numeric','Value',e.(keys{k}),'Limits',limits{k});
            end
            numeric(1).RoundFractionalValues='on';
            uilabel(g,'Text','PE works with fixed or variable windows. Without PE, window switching uses energy detection. Local Huffman books must reduce complete payload bytes, including their metadata. All options default off.', ...
                'WordWrap','on');
            message=uilabel(g,'Text','','FontColor',[.8 .15 .15]);
            apply=uibutton(g,'Text','Apply experiments','ButtonPushedFcn',@(~,~) app.applyExperiments(side));
            app.UI.ExperimentDialog=struct('Figure',fig,'Checks',checks,'Scope',scope,'Numeric',numeric,'Message',message,'Apply',apply);
        end
        function allocationControls(app,side)
            if app.Busy, return; end
            if isfield(app.UI,'Dialog') && isgraphics(app.UI.Dialog.Figure), delete(app.UI.Dialog.Figure); end
            p=app.UI.Side(side).Policy; r=app.UI.Side(side).Reservoir;
            fig=uifigure('Name',['Allocation controls - ' char('A'+side-1)],'Theme','light', ...
                'Position',[180 110 650 560],'WindowStyle','modal');
            g=uigridlayout(fig,[10 1],'RowHeight',{28,42,130,32,32,32,36,'1x',24,32},'RowSpacing',6);
            enabled=uicheckbox(g,'Text','Enable piecewise bit saving','Value',p.enabled);
            uilabel(g,'Text','NMR = error relative to PAM allowance. Lower is better. Above the first boundary, all available refinement bits may be spent.', ...
                'WordWrap','on');
            table=uigridlayout(g,[4 5],'ColumnWidth',{150,65,30,65,'1x'},'RowHeight',{22,26,26,26},'Padding',0);
            uilabel(table,'Text','At / below NMR (dB)'); uilabel(table,'Text','x');
            uilabel(table,'Text',''); uilabel(table,'Text','y'); uilabel(table,'Text','Saving ratio');
            boundary=gobjects(3,1); numerator=boundary; denominator=boundary;
            for k=1:3
                boundary(k)=uieditfield(table,'numeric','Value',p.boundariesDB(k),'Limits',[-60 30]);
                numerator(k)=uieditfield(table,'numeric','Value',p.savedNumerator(k),'Limits',[0 1000],'RoundFractionalValues','on');
                uilabel(table,'Text','in');
                denominator(k)=uieditfield(table,'numeric','Value',p.savedDenominator(k),'Limits',[1 1000],'RoundFractionalValues','on');
                uilabel(table,'Text','bits saved');
            end
            row=uigridlayout(g,[1 2],'ColumnWidth',{270,'1x'},'Padding',0);
            uilabel(row,'Text','Final refinement limit (NMR dB)');
            final=uieditfield(row,'numeric','Value',p.stopDB,'Limits',[-60 30]);
            bucket=uicheckbox(g,'Text','Enable bit bucket (fixed bitrate only)','Value',r.enabled);
            row=uigridlayout(g,[1 4],'ColumnWidth',{125,80,230,'1x'},'Padding',0);
            uilabel(row,'Text','Capacity (frames)');
            capacity=uieditfield(row,'numeric','Value',r.capacityFrames,'Limits',[0 100],'RoundFractionalValues','on');
            uilabel(row,'Text','Saving target when piecewise is off');
            target=uieditfield(row,'numeric','Value',r.targetDB,'Limits',[-60 30]);
            if strcmp(app.UI.Side(side).Mode.Value,'Variable bitrate')
                bucket.Value=false; bucket.Enable='off'; capacity.Enable='off'; target.Enable='off';
            end
            uilabel(g,'Text','Three editable ratios, including the lowest layer. 1 in 1 bits saved stops paid refinement in that layer.', ...
                'WordWrap','on');
            uilabel(g,'Text','VBR uses the cost of reaching the final limit as a finite budget; reserved bits reduce the file. The limit is not a guaranteed achieved NMR. In CBR, enable the bucket to carry savings forward; otherwise they become padding. Full buckets and end of file also produce padding.', ...
                'WordWrap','on','FontColor',[.3 .35 .4]);
            message=uilabel(g,'Text','','FontColor',[.8 .15 .15]);
            apply=uibutton(g,'Text','Apply allocation controls','ButtonPushedFcn',@(~,~) app.applyAllocation(side));
            app.UI.Dialog=struct('Figure',fig,'Enabled',enabled,'Boundary',boundary,'Numerator',numerator, ...
                'Denominator',denominator,'Final',final,'Bucket',bucket,'Capacity',capacity,'Target',target, ...
                'Apply',apply,'Message',message);
        end
    end
    methods (Access=private)
        function build(app)
            app.Figure=uifigure('Name','LAC Listening Lab - CBR / VBR','Theme','light','Position',[80 70 1150 900], ...
                'Color',[.96 .97 .98],'CloseRequestFcn',@(~,~) app.close());
            grid=uigridlayout(app.Figure,[8 1],'RowHeight',{44,34,390,'1x',34,40,86,30}, ...
                'Padding',[16 12 16 12],'RowSpacing',8);
            header=uigridlayout(grid,[1 2],'ColumnWidth',{'1x',450},'Padding',0);
            uilabel(header,'Text','LAC Listening Lab','FontSize',26,'FontWeight','bold');
            uilabel(header,'Text','Original vs codec, or codec vs codec. One shared playback level.', ...
                'HorizontalAlignment','right','FontColor',[.3 .35 .4]);
            top=uigridlayout(grid,[1 4],'ColumnWidth',{55,230,200,'1x'},'Padding',0);
            uilabel(top,'Text','Excerpt');
            app.UI.Source=uidropdown(top,'Items',{'Harpsichord','Castanets','Speech (final test)'}, ...
                'ItemsData',{'harpsichord','castanets','speech'},'ValueChangedFcn',@(~,~) app.markDirty());
            app.UI.Load=uibutton(top,'Text','Load / generate comparison','ButtonPushedFcn',@(~,~) app.loadComparison());
            app.UI.SourceNote=uilabel(top,'Text','Development excerpt. Speech stays reserved until selected.', ...
                'FontSize',11,'WordWrap','on');
            sides=uigridlayout(grid,[1 2],'Padding',0,'ColumnSpacing',12);
            labels={'Tonal vs noise maskers','Temporal masking','Adaptive spreading', ...
                'Enhanced band mapping','Huffman coding','Bandwidth extension (12 kHz)'};
            for s=1:2
                panel=uipanel(sides,'Title',char('A'+s-1),'FontWeight','bold','BackgroundColor','white');
                g=uigridlayout(panel,[12 2],'ColumnWidth',{145,'1x'}, ...
                    'RowHeight',{28,28,22,22,22,22,22,22,28,26,26,'1x'},'Padding',[10 6 10 6],'RowSpacing',3);
                uilabel(g,'Text','Version');
                kind=uidropdown(g,'Items',{'Original','Encoded'},'ValueChangedFcn',@(~,~) app.markDirty());
                if s==2, kind.Value='Encoded'; end
                mode=uidropdown(g,'Items',{'Fixed bitrate','Variable bitrate'}, ...
                    'ValueChangedFcn',@(~,~) app.modeChanged(s));
                rate=uidropdown(g,'Items',{'64 kb/s','96 kb/s','128 kb/s'},'ItemsData',[64 96 128], ...
                    'Value',96,'ValueChangedFcn',@(~,~) app.markDirty());
                checks=gobjects(6,1);
                for k=1:6
                    checks(k)=uicheckbox(g,'Text',labels{k},'ValueChangedFcn',@(~,~) app.markDirty());
                    checks(k).Layout.Row=k+2; checks(k).Layout.Column=[1 2];
                end
                uilabel(g,'Text','Temporal components');
                temporal=uidropdown(g,'Items',{'Post + pre-echo','Post only','Pre-echo only','Bypass'}, ...
                    'ValueChangedFcn',@(~,~) app.markDirty());
                advanced=uibutton(g,'Text','Piecewise saving / bit bucket...', ...
                    'ButtonPushedFcn',@(~,~) app.allocationControls(s));
                advanced.Layout.Column=[1 2]; advanced.Layout.Row=10;
                experiments=uibutton(g,'Text','Codec experiments (5 options)...', ...
                    'ButtonPushedFcn',@(~,~) app.experimentControls(s));
                experiments.Layout.Column=[1 2]; experiments.Layout.Row=11;
                info=uilabel(g,'Text','Not loaded','WordWrap','on','FontSize',11,'FontColor',[.3 .35 .4]);
                info.Layout.Column=[1 2]; info.Layout.Row=12;
                defaults=codec_config();
                app.UI.Side(s)=struct('Kind',kind,'Mode',mode,'Rate',rate,'Checks',checks,'Temporal',temporal, ...
                    'Advanced',advanced,'Policy',defaults.allocation,'Reservoir',defaults.reservoir, ...
                    'ExperimentButton',experiments,'Experiments',defaults.experiments,'Info',info);
            end
            app.UI.Axes=uiaxes(grid); title(app.UI.Axes,'Load a comparison to see the aligned waveforms');
            xlabel(app.UI.Axes,'Time (s)'); ylabel(app.UI.Axes,'Amplitude');
            seekGrid=uigridlayout(grid,[1 2],'ColumnWidth',{'1x',130},'Padding',[10 0 0 0]);
            app.UI.Seek=uislider(seekGrid,'Limits',[0 10],'MajorTicks',[], ...
                'ValueChangedFcn',@(s,~) app.seek(s.Value));
            app.UI.Time=uilabel(seekGrid,'Text','0.000 / 10.000 s','HorizontalAlignment','right');
            transport=uigridlayout(grid,[1 12],'ColumnWidth',{75,75,75,65,35,65,25,65,60,55,'1x',120}, ...
                'Padding',0,'ColumnSpacing',6);
            app.UI.A=uibutton(transport,'Text','Listen A','ButtonPushedFcn',@(~,~) app.select(1));
            app.UI.B=uibutton(transport,'Text','Listen B','ButtonPushedFcn',@(~,~) app.select(2));
            app.UI.Play=uibutton(transport,'Text','Play','ButtonPushedFcn',@(~,~) app.playPause());
            app.UI.Stop=uibutton(transport,'Text','Stop','ButtonPushedFcn',@(~,~) app.stop());
            uilabel(transport,'Text','From');
            app.UI.Start=uieditfield(transport,'numeric','Value',0,'Limits',[0 10], ...
                'ValueChangedFcn',@(~,~) app.regionChanged());
            uilabel(transport,'Text','to');
            app.UI.Finish=uieditfield(transport,'numeric','Value',10,'Limits',[0 10], ...
                'ValueChangedFcn',@(~,~) app.regionChanged());
            app.UI.Loop=uicheckbox(transport,'Text','Loop');
            uilabel(transport,'Text','Volume');
            app.UI.Volume=uislider(transport,'Limits',[0 100],'Value',75,'MajorTicks',[], ...
                'ValueChangedFcn',@(~,~) app.volumeChanged());
            app.UI.Gain=uilabel(transport,'Text','Shared gain: --','FontSize',11);
            notes=uigridlayout(grid,[1 2],'ColumnWidth',{'1x',140},'Padding',0);
            app.UI.Notes=uitextarea(notes,'Placeholder','Listening notes: detail, noise, transients, preference...');
            app.UI.Save=uibutton(notes,'Text','Save listening notes','ButtonPushedFcn',@(~,~) app.saveNotes());
            app.UI.Status=uilabel(grid,'Text','Choose A and B, then load the comparison. All feature switches default off.', ...
                'WordWrap','on','FontSize',11);
        end
        function cfg=selectedConfig(app,side)
            controls=app.UI.Side(side); cfg=codec_config();
            if strcmp(controls.Mode.Value,'Variable bitrate')
                cfg.rateMode='vbr'; cfg.vbr.distortionDB=controls.Rate.Value;
            else
                cfg.targetKbps=controls.Rate.Value;
            end
            names=fieldnames(cfg.features);
            for k=1:6, cfg.features.(names{k})=controls.Checks(k).Value; end
            cfg.pam.temporal.postMasking=ismember(controls.Temporal.Value,{'Post + pre-echo','Post only'});
            cfg.pam.temporal.preEchoControl=ismember(controls.Temporal.Value,{'Post + pre-echo','Pre-echo only'});
            cfg.allocation=controls.Policy; cfg.reservoir=controls.Reservoir;
            cfg.experiments=controls.Experiments;
            if strcmp(cfg.rateMode,'vbr'), cfg.reservoir.enabled=false; end
        end
        function applyExperiments(app,side)
            d=app.UI.ExperimentDialog; e=app.UI.Side(side).Experiments;
            names={'zeroRun','fileHuffman','smartQuantizer','perceptualEntropy','variableWindows'};
            for k=1:5, e.(names{k})=d.Checks(k).Value; end
            keys={'stepRadius','peStrengthDB','attackProtectionDB','attackRatio'};
            for k=1:4, e.(keys{k})=d.Numeric(k).Value; end
            e.huffmanScope=d.Scope.Value; cfg=app.selectedConfig(side); cfg.experiments=e;
            try
                pac.validate_config(cfg);
            catch exception
                d.Message.Text=exception.message; return
            end
            app.UI.Side(side).Experiments=e; delete(d.Figure); app.markDirty();
        end
        function applyAllocation(app,side)
            d=app.UI.Dialog; cfg=app.selectedConfig(side);
            cfg.allocation.enabled=d.Enabled.Value;
            for k=1:3
                cfg.allocation.boundariesDB(k)=d.Boundary(k).Value;
                cfg.allocation.savedNumerator(k)=d.Numerator(k).Value;
                cfg.allocation.savedDenominator(k)=d.Denominator(k).Value;
            end
            cfg.allocation.stopDB=d.Final.Value; cfg.reservoir.enabled=d.Bucket.Value;
            cfg.reservoir.capacityFrames=d.Capacity.Value; cfg.reservoir.targetDB=d.Target.Value;
            try
                pac.validate_config(cfg);
            catch exception
                d.Message.Text=exception.message; return
            end
            app.UI.Side(side).Policy=cfg.allocation;
            if strcmp(cfg.rateMode,'cbr'), app.UI.Side(side).Reservoir=cfg.reservoir; end
            delete(d.Figure); app.markDirty();
        end
        function modeChanged(app,side)
            controls=app.UI.Side(side);
            if strcmp(controls.Mode.Value,'Variable bitrate')
                controls.Rate.ItemsData=[];
                controls.Rate.Items={'Higher quality (-6 dB)','Standard (0 dB)','Smaller file (+6 dB)', ...
                    'Smaller file (+9 dB)','Smallest file (+12 dB)'};
                controls.Rate.ItemsData=[-6 0 6 9 12]; controls.Rate.Value=0;
            else
                controls.Rate.ItemsData=[];
                controls.Rate.Items={'64 kb/s','96 kb/s','128 kb/s'};
                controls.Rate.ItemsData=[64 96 128]; controls.Rate.Value=96;
            end
            app.markDirty();
        end
        function markDirty(app)
            app.stopPlayback(true); app.Dirty=true;
            app.UI.Status.Text='Selections changed. Load / generate comparison to apply them.';
            if strcmp(app.UI.Source.Value,'speech')
                app.UI.SourceNote.Text='Final-test speech: load only after choosing your PAM changes.';
            else
                app.UI.SourceNote.Text='Development excerpt. Speech stays reserved until selected.';
            end
            app.refreshControls();
        end
        function refreshControls(app)
            ready=~app.Dirty && ~app.Busy;
            for c=[app.UI.Play app.UI.Stop app.UI.A app.UI.B app.UI.Save app.UI.Seek app.UI.Start app.UI.Finish]
                c.Enable=app.onOff(ready);
            end
            app.UI.Load.Enable=app.onOff(~app.Busy); app.UI.Source.Enable=app.onOff(~app.Busy);
            for s=1:2
                controls=app.UI.Side(s); controls.Kind.Enable=app.onOff(~app.Busy);
                encoded=strcmp(controls.Kind.Value,'Encoded') && ~app.Busy;
                controls.Rate.Enable=app.onOff(encoded);
                controls.Advanced.Enable=app.onOff(encoded);
                controls.ExperimentButton.Enable=app.onOff(encoded);
                if strcmp(controls.Mode.Value,'Variable bitrate') && controls.Policy.enabled
                    controls.Rate.Enable='off';
                end
                controls.Mode.Enable=app.onOff(encoded);
                for k=1:6, controls.Checks(k).Enable=app.onOff(encoded); end
                controls.Temporal.Enable=app.onOff(encoded && controls.Checks(2).Value);
            end
            app.UI.A.BackgroundColor=[.94 .94 .94]; app.UI.B.BackgroundColor=[.94 .94 .94];
            buttons=[app.UI.A app.UI.B]; buttons(app.Active).BackgroundColor=[.68 .83 .98];
            if app.IsPlaying, app.UI.Play.Text='Pause'; else, app.UI.Play.Text='Play'; end
        end
        function drawWaveform(app)
            ax=app.UI.Axes; cla(ax);
            for s=1:2
                x=app.Data{s}.x; count=ceil(numel(x)/800); padding=mod(-numel(x),count);
                blocks=reshape([x;zeros(padding,1)],count,[]);
                t=((0:size(blocks,2)-1)*count+count/2)/app.Data{s}.fs;
                plot(ax,repelem(t,2),reshape([min(blocks);max(blocks)],1,[]),'LineWidth',.7); hold(ax,'on');
            end
            hold(ax,'off'); xlim(ax,[0 app.Duration]); grid(ax,'on');
            legend(ax,{'A','B'},'Location','northeast'); title(ax,'Aligned waveforms (original levels)');
            xlabel(ax,'Time (s)'); ylabel(ax,'Amplitude');
            app.Marker=xline(ax,0,'k-','LineWidth',1.2,'HandleVisibility','off');
        end
        function updateGain(app)
            peak=max([1;abs(app.Data{1}.x);abs(app.Data{2}.x)]);
            app.Gain=.98*(app.UI.Volume.Value/100)/peak;
            app.UI.Gain.Text=sprintf('Shared gain: %.3f',app.Gain);
        end
        function volumeChanged(app)
            if app.Dirty || app.Busy, return; end
            wasPlaying=app.IsPlaying; app.stopPlayback(true); app.updateGain();
            if wasPlaying, app.startPlayback(); end
        end
        function regionChanged(app)
            app.stopPlayback(false);
            if app.UI.Finish.Value-app.UI.Start.Value<.02
                app.UI.Start.Value=0; app.UI.Finish.Value=app.Duration;
                app.UI.Status.Text='Region must be at least 0.02 seconds. Restored the full clip.';
            end
            app.Cursor=app.UI.Start.Value; app.updatePosition();
        end
        function startPlayback(app)
            if app.Dirty || app.Busy, return; end
            if app.Cursor<app.UI.Start.Value || app.Cursor>=app.UI.Finish.Value-.0001
                app.Cursor=app.UI.Start.Value;
            end
            fs=app.Data{app.Active}.fs; first=floor(app.Cursor*fs)+1;
            last=min(numel(app.Data{app.Active}.x),floor(app.UI.Finish.Value*fs));
            app.SegmentStart=(first-1)/fs; app.PlayToken=app.PlayToken+1; token=app.PlayToken;
            try
                player=audioplayer(app.Gain*app.Data{app.Active}.x(first:last),fs,24);
                player.TimerPeriod=.05;
                player.TimerFcn=@(p,~) app.tick(p,token);
                player.StopFcn=@(p,~) app.finished(p,token);
                app.Player=player; app.IsPlaying=true; play(player);
                app.UI.Status.Text=sprintf('Playing %s. A/B switches keep the same sample position.',char('A'+app.Active-1));
            catch exception
                app.IsPlaying=false; app.Player=[];
                app.UI.Status.Text=['Playback unavailable: ' exception.message];
            end
            app.refreshControls();
        end
        function stopPlayback(app,keepPosition)
            app.PlayToken=app.PlayToken+1;
            if ~isempty(app.Player)
                if keepPosition && app.IsPlaying
                    app.Cursor=min(app.UI.Finish.Value,app.SegmentStart+max(0,app.Player.CurrentSample-1)/48000);
                end
                app.Player.TimerFcn=[]; app.Player.StopFcn=[]; stop(app.Player); app.Player=[];
            end
            app.IsPlaying=false;
            if ~app.Closing && isgraphics(app.Figure), app.refreshControls(); end
        end
        function tick(app,player,token)
            if app.Closing || token~=app.PlayToken || ~isgraphics(app.Figure), return; end
            app.Cursor=min(app.UI.Finish.Value,app.SegmentStart+max(0,player.CurrentSample-1)/48000);
            app.updatePosition();
        end
        function finished(app,~,token)
            if app.Closing || token~=app.PlayToken || ~isgraphics(app.Figure), return; end
            app.Player=[]; app.IsPlaying=false; app.Cursor=app.UI.Finish.Value; app.updatePosition();
            if app.UI.Loop.Value && ~app.Dirty
                app.Cursor=app.UI.Start.Value; app.startPlayback();
            else
                app.refreshControls(); app.UI.Status.Text='Playback finished.';
            end
        end
        function updatePosition(app)
            app.UI.Seek.Value=max(0,min(app.Duration,app.Cursor));
            app.UI.Time.Text=sprintf('%.3f / %.3f s',app.Cursor,app.Duration);
            if ~isempty(app.Marker) && isgraphics(app.Marker), app.Marker.Value=app.Cursor; end
        end
    end
    methods (Static,Access=private)
        function value=onOff(flag)
            if flag, value='on'; else, value='off'; end
        end
    end
end
