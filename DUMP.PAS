unit dump;

interface

uses midifile, midiutil;

procedure dump_meta(var p: pbyte; var count: longint; quiet: boolean);
procedure dump_sysex(var p: pbyte; var count: longint; quiet: boolean);
procedure dump_track(num: word; var m: TMidifile; quiet: boolean);

implementation

procedure dump_meta(var p: pbyte; var count: longint; quiet: boolean);
var
    this_count: byte;
    meta_len: longint;
    kind: byte;
    tempo: longint;
begin
    kind:=p^;
    inc(p);
    count:=1;

    scan_varint(p, this_count, meta_len);
    count:=count+this_count;

    if (not quiet) then begin
        write('Meta ', hex(kind), ' len=', meta_len, ' ');
    end;

    if (kind = $51) then begin
        scan_3byte(p, tempo);
        count:=count+3;
        writeln('tempo ', tempo);
    end else begin
        count:=count+meta_len;
        inc(p, meta_len);
        writeln;
    end;
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
        writeln('Sysex ', hex(kind), ' len=', meta_len, ' ');
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
        writeln('Sysex manufacturer=', hex(kind), ' length=', count, ' ');
    end;
end;

type
    TChanUsed = array[0..15] of boolean;

procedure dump_eot(m: TMidiFile;
                   msg: string;
                   track_num: word;
                   count: longint;
                   event_count: word;
                   sysex_count: word;
                   meta_count: word;
                   max_delta: longint;
                   var channels_used: TChanUsed);
var
    i: integer;
begin
    writeln(msg,': count=', count,
            ' events=', event_count,
            ' sysex=', sysex_count,
            ' meta=', meta_count,
            ' max_d=', max_delta);
    if (count < m.tracks[track_num].length) then begin
        writeln('    count ', count, ' is less than track len ', m.tracks[track_num].length);
    end;
    { note that 0=Channel 1, 1=Channel2, etc }
    write('channels_used: ');
    for i:=0 to 15 do begin
        if channels_used[i] then begin
            write(i+1, ' ');
        end;
    end;
    writeln;
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
    channels_used: TChanUsed;
    max_delta: longint;
    i: integer;
begin
    count:=0;
    meta_count:=0;
    sysex_count:=0;
    event_count:=0;
    max_delta:=0;
    fillchar(channels_used, sizeof(channels_used), 0);
    p:=m.tracks[num].raw;
    while (count < m.tracks[num].length) do begin
        inc(event_count);
        scan_varint(p, this_count, delta);
        count := count + this_count;
        if (delta>max_delta) then begin
            max_delta:=delta;
        end;
        msg := p^;
        inc(p);
        inc(count);
        if (not quiet) then write(' ', delta:8, ' ', hex(msg), ' ');
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
                dump_eot(m, 'end of track', num, count, event_count, sysex_count, meta_count, max_delta, channels_used);
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
            channels_used[msg and $F]:=true;
        end else if (msg >= $90) and (msg <= $9F) then begin;
            kk:=p^;
            inc(p);
            inc(count);
            vv:=p^;
            inc(p);
            inc(count);
            if (not quiet) then writeln('On ', kk, ' ', vv);
            channels_used[msg and $F]:=true;
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
    dump_eot(m, 'end of loop', num, count, event_count, sysex_count, meta_count, max_delta, channels_used);
end;

end.