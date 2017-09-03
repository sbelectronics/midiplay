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
    debug, debug_isr: boolean;
    i: integer;
    param: string;
    remap: TRemap;
begin;
    do_dump:=false;
    do_playback:=false;
    do_help:=false;
    do_primes:=false;
    quiet:=false;
    polling:=false;
    debug:=false;
    debug_isr:=false;
    remap:=REMAP_PLUS_ONE;
    filename:='';
    fix_stdio;
    for i:=1 to ParamCount do begin
        param:=upstr(ParamStr(i));
        if (param = '-D') then begin
            do_dump:=true;
        end else if (param = '-Q') then begin
            quiet:=true;
        end else if (param = '-P') then begin
            do_playback:=true;
        end else if (param = '-O') then begin
            polling:=true;
        end else if (param = '-H') then begin
            do_help:=true;
        end else if (param = '-R') then begin
            do_primes:=true;
        end else if (param = '-V') then begin
            debug:=true;
        end else if (param = '-VV') then begin
            debug_isr:=true;
        end else if (param = '-M0') then begin
            remap:=REMAP_NONE;
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

    load_midi_file(filename, midi_file, remap);
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
        mpu401_set_debug(debug, debug_isr);
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