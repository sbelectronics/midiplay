{
  midiplay.pas
  Scott M Baker
  http://www.smbaker.com/

  Main unit for the midi player. Processes command line arguments,
  initializes things, complains, etc.
}

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

{
  bruteprime

  Waste cpu cycles computing primes in a very inefficient way. This is to
  prove we can do useful work while playing midi files
}

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
       if mpu401_done_playing then begin
           writeln('Song Complete.');
           exit;
       end;
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
    writeln('MPU-401 Intelligent Mode Player');
    writeln('Dr Scott M. Baker');
    writeln('http://www.smbaker.com/');
    writeln;

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

    if (not do_playback) and (not do_dump) then begin
        writeln('(Hint: use "-H" for help or "-P <filename.mid>" to play a file)');
        writeln;
    end;

    if (filename='') or (do_help) then begin
        writeln('Syntax: midiplay [options] filename.mid');
        writeln('   -H show help');
        writeln('   -P play file');
        writeln('   -D dump');
        writeln('   -Q when dumping, dump quietly');
        writeln('   -O use polling instead of ISR');
        writeln('   -R compute prime numbers while doing background playback');
        writeln('   -M0 do not remap tracks');
        writeln('   -V be somewhat verbose');
        writeln('   -VV be even more verbose');
        exit;
    end;

    load_midi_file(filename, midi_file, remap, debug);
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
                while (not keypressed) and (not mpu401_done_playing) do delay(100);
                if mpu401_done_playing then begin
                    writeln('Song Complete.');
                end;
            end;
        end;
        mpu401_stop_play;
        { stack_analysis; }
    end;
end.