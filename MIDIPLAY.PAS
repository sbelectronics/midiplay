uses midifile, dump, midiutil, mpu401, crt;

procedure fix_stdio;
var
    screen: text;
begin
    assign(output, '');
    rewrite(output);
    assignCrt(screen);
    rewrite(screen);
end;


var
    midi_file: TMidiFile;
    filename: string;
    do_dump, do_playback, do_help, quiet, polling: boolean;
    i: integer;
begin;
    do_dump:=false;
    do_playback:=false;
    do_help:=false;
    quiet:=false;
    polling:=false;
    filename:='';
    fix_stdio;
    for i:=1 to ParamCount do begin
        if ((ParamStr(i) = '-D') or (ParamStr(i)= '-d')) then begin;
{            fix_stdio;}
            do_dump:=true;
        end else if ((ParamStr(i) = '-Q') or (ParamStr(i)= '-q')) then begin;
            quiet:=true;
        end else if ((ParamStr(i) = '-P') or (ParamStr(i)= '-p')) then begin;            quiet:=true;
            do_playback:=true;
        end else if ((ParamStr(i) = '-O') or (ParamStr(i)= '-o')) then begin;            quiet:=true;
            polling:=true;
        end else if ((ParamStr(i) = '-H') or (ParamStr(i)= '-h')) then begin;            quiet:=true;
            do_help:=true;
        end else begin;
            filename:=ParamStr(i);
        end;
    end;

    if (filename='') or (do_help) then begin
        writeln('Syntax: midiplay [-D] filename.mid');
        writeln('   -P play file');
        writeln('   -D dump');
        writeln('   -Q when dumping, dump quietly');
        writeln('   -O use polling instead of ISR');
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
        mpu401_init(MPU401_DEFAULT_PORT, MPU401_DEFAULT_IRQ, not polling);
        mpu401_play_file(midi_file);
        if polling then begin;
            writeln('polling');
            mpu401_polling;
        end else begin;
            writeln('press a return to exit');
            readln;
    {        while (not mpu401_idle) do begin
                writeln('idling');
                delay(1000); { do nothing
            end; }
        end;
    end;
end.