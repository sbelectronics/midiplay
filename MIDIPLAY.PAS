uses midifile, dump, midiutil;

var
    midi_file: TMidiFile;
    filename: string;
    do_dump, quiet: boolean;
    i: integer;
begin;
    do_dump:=false;
    quiet:=false;
    filename:='';
    for i:=1 to ParamCount do begin
        if ((ParamStr(i) = '-D') or (ParamStr(i)= '-d')) then begin;
            do_dump:=true;
        end else if ((ParamStr(i) = '-Q') or (ParamStr(i)= '-q')) then begin;
            quiet:=true;
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
end.