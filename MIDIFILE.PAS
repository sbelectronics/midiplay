unit midifile;

interface

const
   MAX_TRACK=16;
   NO_DELTA_LEFT=10000000;
type
   Pbyte = ^byte;
   TRemap = (REMAP_PLUS_ONE, REMAP_NONE);
   TTrack = record
             length: longint;
             raw: Pbyte;
             play_ptr: Pbyte;
             play_count: word;
             delta_left: longint;
             complete: boolean;
             last_msg: byte;
   end;
   TMidiFile = record
       length: longint;
       format: word;
       num_tracks: word;
       division: word;

       cur_track: word;
       tracks: array[0..(MAX_TRACK-1)] of TTrack;
       track_map: array[0..15] of byte;
       track_reverse_map: array[0..15] of byte;
       channel_map: array[0..15] of byte;
       channel_msg_map: array[0..255] of byte;

       enable_conductor: boolean;
       conductor_track_num: byte;
   end;

procedure load_midi_file(fn: string; var midifile: TMidifile; remap: TRemap);

implementation

uses midiutil;

procedure load_header(var f: file; var m: TMidiFile);
var
    chunk: string;
begin;
    FillChar(m, sizeof(m), 0);

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

procedure generate_track_map(var m: TMidiFile; remap: TRemap);
var
    i: integer;
begin
    if (remap=REMAP_NONE) then begin
        for i:=1 to 15 do begin
            m.track_map[i]:=i;
        end;
    end else begin
        { track 0 is for meta messages, so remap track 1 to 0, 2 to 1, ... }
        for i:=1 to 15 do begin
            m.track_map[i]:=i-1;
        end;
        m.track_map[0]:=15;

        m.enable_conductor:=false;   { true;    not working yet... }
        m.conductor_track_num:=0;
    end;

    { channel map is just straight through }
    for i:=0 to 15 do begin
        m.channel_map[i]:=i;
    end;
end;

procedure generate_voice_map(var m: TMidiFile);
var
    trk, chan: byte;
    i: integer;
begin
    for i:=0 to 15 do begin
        trk:=m.track_map[i];
        m.track_reverse_map[trk]:=i;
    end;

    for i:=0 to 15 do begin
        chan:=m.channel_map[i];

        m.channel_msg_map[$80 + i] := $80+chan;
        m.channel_msg_map[$90 + i] := $90+chan;
        m.channel_msg_map[$A0 + i] := $A0+chan;
        m.channel_msg_map[$B0 + i] := $B0+chan;
        m.channel_msg_map[$C0 + i] := $C0+chan;
        m.channel_msg_map[$D0 + i] := $D0+chan;
        m.channel_msg_map[$E0 + i] := $E0+chan;
    end;
end;

procedure load_midi_file(fn: string; var midifile: TMidifile; remap: TRemap);
var
    mf: file;
begin
    assign(mf, fn);
    reset(mf,1);
    load_header(mf, midifile);
    while (not eof(mf)) do begin
        load_chunk(mf, midifile);
    end;
    generate_track_map(midifile, remap);
    generate_voice_map(midifile);
end;

end.
