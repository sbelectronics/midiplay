uses midifile, dump, midiutil, mpu401;

procedure playback_midi_file(var midi_file: TMidiFile);
begin
    mpu401_init(MPU401_DEFAULT_PORT, MPU401_DEFAULT_IRQ);
    { need to setup ISR here... }
    mpu401_start_play($FF); { all tracks }
    while (not mpu401_idle()) do begin
        delay(1000); { do nothing }
    end;
end;

var
    midi_file: TMidiFile;
    filename: string;
    do_dump, do_playback, quiet: boolean;
    i: integer;
begin;
    do_dump:=false;
    do_playback:=false;
    quiet:=false;
    filename:='';
    for i:=1 to ParamCount do begin
        if ((ParamStr(i) = '-D') or (ParamStr(i)= '-d')) then begin;
            do_dump:=true;
        end else if ((ParamStr(i) = '-Q') or (ParamStr(i)= '-q')) then begin;
            quiet:=true;
        end else if ((ParamStr(i) = '-P') or (ParamStr(i)= '-p')) then begin;            quiet:=true;
            do_playback:=true;
        end else begin;
            filename:=ParamStr(i);
        end;
    end;

    if (filename='') then begin
        writeln('Syntax: midiplay [-D] filename.mid');
        exit;
    end;

    load_midi_file(filename, midi_file);
    writeln('Format=', midi_file.format,
            ' Tracks=', midi_file.num_tracks,
            ' Division=', midi_file.division);

    if (do_dump) then begin
        for i:=0 to midi_file.cur_track-1 do begin
           writeln('=== Dump Track ', i, ' ===');
           dump_track(i, midi_file, quiet);
        end;
    end;

    if (do_playback) then begin
        playback_midi_file(midi_file);
    end;
end.