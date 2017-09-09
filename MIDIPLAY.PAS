{
  midiplay.pas
  Scott M Baker
  http://www.smbaker.com/

  Main unit for the midi player. Processes command line arguments,
  initializes things, complains, etc.
}

uses midiopt, midifile, dump, midiutil, mpu401, crt;

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
    opts: TMidiOptions;
    filename: string;
    i: integer;
    param: string;
begin;
    writeln('MPU-401 Intelligent Mode Player');
    writeln('Dr Scott M. Baker');
    writeln('http://www.smbaker.com/');
    writeln;

    filename:='';
    fix_stdio;
    set_default_options(opts);
    for i:=1 to ParamCount do begin
        param:=upstr(ParamStr(i));
        if (param = '-D') then begin
            opts.do_dump:=true;
        end else if (param = '-Q') then begin
            opts.quiet:=true;
        end else if (param = '-P') then begin
            opts.do_playback:=true;
        end else if (param = '-O') then begin
            opts.polling:=true;
        end else if (param = '-H') then begin
            opts.do_help:=true;
        end else if (param = '-K') then begin
            opts.reset:=false;
        end else if (param = '-R') then begin
            opts.do_primes:=true;
        end else if (param = '-V') then begin
            opts.debug:=true;
        end else if (param = '-VV') then begin
            opts.debug_isr:=true;
        end else if (param = '-M0') then begin
            opts.remap:=REMAP_NONE;
        end else begin;
            filename:=ParamStr(i);
        end;
    end;

    if (not opts.do_playback) and (not opts.do_dump) then begin
        writeln('(Hint: use "-H" for help or "-P <filename.mid>" to play a file)');
        writeln;
    end;

    if (filename='') or (opts.do_help) then begin
        writeln('Syntax: midiplay [options] filename.mid');
        writeln('   -H show Help');
        writeln('   -P Play file');
        writeln('   -D Dump');
        writeln('   -K Keep midi config (aka do not reset)');
        writeln('   -Q when dumping, dump Quietly');
        writeln('   -O use pOlling instead of ISR');
        writeln('   -R compute pRime numbers while doing background playback');
        writeln('   -M0 do not reMap tracks');
        writeln('   -V be somewhat Verbose');
        writeln('   -VV be even more Verbose');
        exit;
    end;

    load_midi_file(filename, midi_file, opts);
    writeln('Format=', midi_file.format,
            ' Tracks=', midi_file.num_tracks,
            ' Division=', midi_file.division);

    if (opts.do_dump) then begin
        for i:=0 to midi_file.cur_track-1 do begin
           writeln('=== Dump Track ', i, ' ===');
           dump_track(i, midi_file, opts);
        end;
    end;

    if (opts.do_playback) then begin
        mpu401_init(MPU401_DEFAULT_PORT, MPU401_DEFAULT_IRQ, opts);
        mpu401_play_file(midi_file);
        if opts.polling then begin;
            writeln('polling -- press any key to exit');
            mpu401_polling;
        end else begin;
            writeln('background playing -- press any key to exit');
            if (opts.do_primes) then begin
                bruteprime;
            end else begin
                while (not keypressed) and (not mpu401_done_playing) do begin
                    delay(100);
                end;
                if mpu401_done_playing then begin
                    writeln('Song Complete.');
                end;
            end;
        end;
        mpu401_stop_play;
        stack_analysis;
    end;
end.