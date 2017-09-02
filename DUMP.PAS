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

end.