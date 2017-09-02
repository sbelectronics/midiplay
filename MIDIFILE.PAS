unit midifile;

interface

const
   MAX_TRACK=16;
   NO_DELTA_LEFT=10000000;
type
   Pbyte = ^byte;
   TTrack = record
             length: longint;
             raw: Pbyte;
             play_ptr: Pbyte;
             play_count: word;
             delta_left: longint;
             complete: boolean;
   end;
   TMidiFile = record
       length: longint;
       format: word;
       num_tracks: word;
       division: word;

       cur_track: word;
       tracks: array[0..(MAX_TRACK-1)] of TTrack;
   end;

procedure load_midi_file(fn: string; var midifile: TMidifile);

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

procedure load_midi_file(fn: string; var midifile: TMidifile);
var
    mf: file;
begin
    assign(mf, fn);
    reset(mf,1);
    load_header(mf, midifile);
    while (not eof(mf)) do begin
        load_chunk(mf, midifile);
    end;
end;

end.
