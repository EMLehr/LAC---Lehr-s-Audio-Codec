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
                        label=sprintf('%s | target %d, actual %.3f kb/s | %s bytes', ...
                            strrep(d.model,'_',' '),d.config.targetKbps,d.actualKbps,string(d.bytes));
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
            if isgraphics(app.Figure), delete(app.Figure); end
        end
    end
    methods (Access=private)
        function build(app)
            app.Figure=uifigure('Name','LAC Listening Lab','Theme','light','Position',[80 70 1150 900], ...
                'Color',[.96 .97 .98],'CloseRequestFcn',@(~,~) app.close());
            grid=uigridlayout(app.Figure,[8 1],'RowHeight',{44,34,310,'1x',34,40,86,30}, ...
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
                g=uigridlayout(panel,[10 2],'ColumnWidth',{145,'1x'}, ...
                    'RowHeight',{28,28,22,22,22,22,22,22,28,'1x'},'Padding',[10 6 10 6],'RowSpacing',3);
                uilabel(g,'Text','Version');
                kind=uidropdown(g,'Items',{'Original','Encoded'},'ValueChangedFcn',@(~,~) app.markDirty());
                if s==2, kind.Value='Encoded'; end
                uilabel(g,'Text','Target bitrate');
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
                info=uilabel(g,'Text','Not loaded','WordWrap','on','FontSize',11,'FontColor',[.3 .35 .4]);
                info.Layout.Column=[1 2]; info.Layout.Row=10;
                app.UI.Side(s)=struct('Kind',kind,'Rate',rate,'Checks',checks,'Temporal',temporal,'Info',info);
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
            controls=app.UI.Side(side); cfg=codec_config(); cfg.targetKbps=controls.Rate.Value;
            names=fieldnames(cfg.features);
            for k=1:6, cfg.features.(names{k})=controls.Checks(k).Value; end
            cfg.pam.temporal.postMasking=ismember(controls.Temporal.Value,{'Post + pre-echo','Post only'});
            cfg.pam.temporal.preEchoControl=ismember(controls.Temporal.Value,{'Post + pre-echo','Pre-echo only'});
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
