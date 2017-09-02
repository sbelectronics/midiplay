type
   Pbyte = ^byte;
   TTrack = record
             length: longint;
             raw: Pbyte;
   end;
   TMidiFile = record
       length: longint;
       format: word;
       num_tracks: word;
       division: word;

       cur_track: word;
       tracks: array[0..15] of TTrack;
   end;

procedure scan_varint(var p: Pbyte; var count: byte; var dest: longint);
var
    b: byte;
begin
    dest:=0;
    count:=0;
    while (true) do begin
        b:=p^;
        inc(p);
        count:=count+1;
        dest:=(dest shl 7) + (b and 127);
        if (b<128) then begin
            exit;
        end;
        b:=1;
    end;
end;


procedure read_be_word(var f: file; var dest: word);
begin
  blockread(f, dest, 2);
  dest:=swap(dest);
end;


procedure read_be_longint(var f: file; var dest: longint);
var
  b: byte;
begin
  blockread(f, b, 1);
  dest:=b;
  blockread(f, b, 1);
  dest:=(dest shl 8)+b;
  blockread(f, b, 1);
  dest:=(dest shl 8)+b;
  blockread(f, b, 1);
  dest:=(dest shl 8)+b;
end;

procedure load_header(var f: file; var m: TMidiFile);
var
    chunk: string;
begin;
    blockread(f, chunk[1], 4);
    chunk[0]:=chr(4);
    if (chunk <> 'MThd') then begin
        writeln('Header chunk is wrong type:', chunk);
        halt;
    end;
    read_be_longint(f, m.length);
    if (m.length <> 6) then begin
        writeln('header length is wrong:', m.length);
        halt;
    end;
    read_be_word(f, m.format);
    read_be_word(f, m.num_tracks);
    read_be_word(f, m.division);
    m.cur_track := 0;
end;

procedure load_chunk(var f: file; var m: TMidiFile);
var
    chunk: string;
    length, readlength: longint;
    skip: longint;
begin
    blockread(f, chunk[1], 4);
    chunk[0]:=chr(4);
    read_be_longint(f, length);
    if (chunk <> 'MTrk') then begin
        writeln('Skip ', chunk);
        seek(f, filepos(f) + length);
    end;
    writeln('Read Track length=', length);

    skip:=0;
    readlength:=length;
    if (length > 65535) then begin
        { crop it to 65000 so we force stop playing before we run into
          the end of the buffer.
        }
        writeln('Crop track to 65000');
        skip:=length-65535;
        readlength:=65535;
        length:=65000;
    end;

    m.tracks[m.cur_track].length:=length;
    getmem(m.tracks[m.cur_track].raw, length);
    blockread(f, m.tracks[m.cur_track].raw^, readlength);

    if (skip>0) then begin
        seek(f, filepos(f) + skip);
    end;

    inc(m.cur_track);
end;

procedure dump_meta(var p: pbyte; var count: longint; quiet: boolean);
var
    this_count: byte;
    meta_len: longint;
    kind: byte;
begin
    kind:=p^;
    inc(p);
    count:=1;

    scan_varint(p, this_count, meta_len);
    count:=count+this_count;

    if (not quiet) then begin
        writeln('Meta ', kind, ' ', meta_len, ' ');
    end;

    count:=count+meta_len;
    inc(p, meta_len);
end;

procedure dump_sysex_bad(var p: pbyte; var count: longint; quiet: boolean);
var
    this_count: byte;
    meta_len: longint;
    kind: byte;

    i: integer;
    q: pbyte;
begin
    kind:=p^;
    inc(p);
    count:=1;

    scan_varint(p, this_count, meta_len);
    count:=count+this_count;

    if (not quiet) then begin
        writeln('Sysex ', kind, ' ', meta_len, ' ');
    end;

    count:=count+meta_len;
    inc(p, meta_len);
end;

procedure dump_sysex(var p: pbyte; var count: longint; quiet: boolean);
var
    this_count: byte;
    meta_len: longint;
    kind: byte;

    i: integer;
    q: pbyte;
begin
    kind:=p^;
    count:=0;

    while (p^ <> $F7) do begin
       inc(p);
       inc(count);
    end;

    inc(p);
    inc(count);

    if (not quiet) then begin
        writeln('Sysex manufacturer=', kind, ' length=', count, ' ');
    end;
end;

procedure dump_track(num: word; var m: TMidifile; quiet: boolean);
var
    p: pbyte;
    count: longint;
    this_count: byte;
    event_count, sysex_count, meta_count: word;
    meta_len: longint;
    delta: longint;
    msg, last_msg: byte;
    meta: byte;
    kk, vv: byte;
begin
    count:=0;
    meta_count:=0;
    sysex_count:=0;
    event_count:=0;
    p:=m.tracks[num].raw;
    while (count < m.tracks[num].length) do begin
        inc(event_count);
        scan_varint(p, this_count, delta);
        count := count + this_count;
        msg := p^;
        inc(p);
        inc(count);
        if (not quiet) then write(' ', delta, ' ');
        if (msg <= $7F) then begin
            { running status }
            dec(p);
            dec(count);
            msg:=last_msg;
        end;
        if (msg = $F0) then begin;
            dump_sysex(p, meta_len, quiet);
            count:=count+meta_len;
            inc(sysex_count);
        end else if (msg = $F7) then begin;
            { escape sysex }
            if (not quiet) then writeln('sysex escape');
        end else if (msg = $FF) then begin
            meta:=p^;
            dump_meta(p, meta_len, quiet);
            count:=count+meta_len;
            inc(meta_count);
            if (meta = $2F) then begin
                { end of track }
                writeln('end track count=', count,
                        ' length=', m.tracks[num].length,
                        ' events=', event_count,
                        ' sysex=', sysex_count,
                        ' meta=', meta_count);
                exit;
            end;
        end else if (msg >= $80) and (msg <= $8F) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            vv:=p^;
            inc(p);
            inc(count);
            if (not quiet) then writeln('Off ', kk, ' ', vv);
        end else if (msg >= $90) and (msg <= $9F) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            vv:=p^;
            inc(p);
            inc(count);
            if (not quiet) then writeln('On ', kk, ' ', vv);
        end else if (msg >= $A0) and (msg <= $AF) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            vv:=p^;
            inc(p);
            inc(count);
            if (not quiet) then writeln('After ', kk, ' ', vv);
        end else if (msg >= $B0) and (msg <= $BF) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            vv:=p^;
            inc(p);
            inc(count);
            if (not quiet) then writeln('Control ', kk, ' ', vv);
        end else if (msg >= $C0) and (msg <= $CF) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            if (not quiet) then  writeln('Program ', kk);
        end else if (msg >= $D0) and (msg <= $DF) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            vv:=p^;
            inc(p);
            inc(count);
            if (not quiet) then writeln('Pres ', kk, ' ', vv);
        end else if (msg >= $E0) and (msg <= $EF) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            vv:=p^;
            inc(p);
            inc(count);
            if (not quiet) then writeln('Pitch ', kk, ' ', vv);
        end else begin
            writeln('unknown msg ', msg);
            halt;
        end;
        last_msg := msg;
    end;
    writeln('end of dump loop count=', count,
            ' length=', m.tracks[num].length,
            ' events=', event_count,
            ' sysex=', sysex_count,
            ' meta=', meta_count);
end;

var
    mf: file;
    midifile: TMidiFile;
    filename: string;
    dump, quiet: boolean;
    i: integer;
begin;
    dump:=false;
    filename:='';
    for i:=1 to ParamCount do begin
        if ((ParamStr(i) = '-D') or (ParamStr(i)= '-d')) then begin;
            dump:=true;
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

    assign(mf, filename);
    reset(mf,1);
    load_header(mf, midifile);
    writeln('Format=', midifile.format, ' Tracks=', midifile.num_tracks, ' Division=', midifile.division);
    while (not eof(mf)) do begin
        load_chunk(mf, midifile);
    end;

    if (dump) then begin
        for i:=0 to midifile.cur_track-1 do begin
           writeln('=== Dump Track ', i, ' ===');
           dump_track(i, midifile, quiet);
        end;
    end;
end.