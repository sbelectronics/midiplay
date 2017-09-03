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

procedure bruteprime;
var
    n,d: longint;
    divided: boolean;
begin
    n:=3;
    while true do begin
       divided:=false;
       d:=2;
       while (d<=(n-1)) and (not divided) do begin
           if (n mod d)=0 then begin
               write('.');
               divided:=true;
           end;
           inc(d);
       end;
       if (not divided) then begin
           write(n);
       end;
       n:=n+1;
       if keypressed then begin
           exit;
       end;
    end;
end;


var
    midi_file: TMidiFile;
    filename: string;
    do_dump, do_playback, do_help, do_primes, quiet, polling: boolean;
    i: integer;
begin;
    do_dump:=false;
    do_playback:=false;
    do_help:=false;
    do_primes:=false;
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
        end else if ((ParamStr(i) = '-P') or (ParamStr(i)= '-p')) then begin;
            do_playback:=true;
        end else if ((ParamStr(i) = '-O') or (ParamStr(i)= '-o')) then begin;
            polling:=true;
        end else if ((ParamStr(i) = '-H') or (ParamStr(i)= '-h')) then begin;
            do_help:=true;
        end else if ((ParamStr(i) = '-R') or (ParamStr(i)= '-r')) then begin;
            do_primes:=true;
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
        writeln('   -R compute prime numbers while doing background playback');
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
            writeln('polling -- press any key to exit');
            mpu401_polling;
        end else begin;
            writeln('background playing -- press any key to exit');
            if (do_primes) then begin
                bruteprime;
            end else begin
                while (not keypressed) do delay(100);
            end;
    {        while (not mpu401_idle) do begin
                writeln('idling');
                delay(1000); { do nothing
            end; }
        end;
        mpu401_stop_play;
    end;
end.