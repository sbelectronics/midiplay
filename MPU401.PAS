{
  MPU401 Intelligent Mode Interface

  Scott Baker
  http://www.smbaker.com/

  This unit implements an interface to the MPU401 in intelligent mode.
  Start by calling mpu401_init(). Then call mpu401_play_file().
  After that, the MPU-401 will send track data requests
      The ISR will handle the track data requests

  This is all 100% untested. I don't even have my MT-32 or MPU-401 yet.
}

unit mpu401;

interface

uses dos, crt, midifile, midiutil;

const
    MPU401_DEFAULT_PORT = $330;
    MPU401_DEFAULT_IRQ = 9;
    DSR = 128;
    DRR = 64;
var
    debug: boolean;
    isr_debug: boolean;

{ low-level operations }
procedure mpu401_init(aport: word; anirq: word; install_isr: boolean);
procedure mpu401_send_command(b: byte);
procedure mpu401_send_data(b: byte);
function mpu401_get_data: byte;

{ intermediate operations }
procedure mpu401_start_play(trackmask: byte; division: word);
procedure mpu401_stop_play;

{ high-level operations }
procedure mpu401_play_file(var m: TMidiFile);
function mpu401_idle: boolean;

procedure mpu401_handle_data(b: byte);

procedure mpu401_polling;

implementation

var
    com_port, stat_port, data_port: word;
    irq,vec: word;
    m_playing: TMidiFile;
    old_exitproc, old_intvec: Pointer;

procedure disable_int;
begin
  { disable interrupts }
  asm;
     cli
  end;
end;

procedure enable_int;
begin
  { enable interrupts }
  asm;
    sti
  end;
end;

procedure mpu401_send_command(b: byte);
var
  data: byte;
begin
  if (debug) then writeln('send_command: wait for DRR');

  { poll for DRR (bit 6) to be 0 }
  while (port[stat_port] and DRR)=DRR do begin
  end;

  if (debug) then writeln('send_command: DRR ready');

  disable_int;

  port[com_port]:=b;

  { poll for DSR (bit 7) to be 0 }
  while (port[stat_port] and DSR)=DSR do begin
  end;

  repeat
     data:=port[data_port];
     if (data <> $FE) then begin
         mpu401_handle_data(data); { call isr }
     end;
  until (data = $FE);

  enable_int;

  if (debug) then writeln('send_command: complete');
end;

procedure mpu401_send_data(b: byte);
begin
  { poll for DRR (bit 6) to be 0 }
  while (port[stat_port] and DRR)=DRR do begin
  end;

  if (isr_debug) then writeln('send data ',b);

  port[data_port] := b;
end;

function mpu401_get_data: byte;
begin
  { poll for DSR (bit 7) to be 0 }
  while (port[stat_port] and DSR)=DSR do begin
  end;

  mpu401_get_data := port[data_port];
end;

function division_to_timebase(division: word): byte;
begin
    if (division >= 192) then begin
        division_to_timebase:=$C8;
    end else if (division >= 168) then begin
        division_to_timebase:=$C7;
    end else if (division >= 144) then begin
        division_to_timebase:=$C6;
    end else if (division >= 120) then begin
        division_to_timebase:=$C5;
    end else if (division >= 96) then begin
        division_to_timebase:=$C4;
    end else if (division >= 72) then begin
        division_to_timebase:=$C3;
    end else begin
        division:=$C2;
    end;
end;

procedure mpu401_start_play(trackmask: byte; division: word);
begin
    if (debug) then writeln('starting start_play');
    mpu401_send_command(division_to_timebase(division));
    mpu401_send_command($EC);     { activate tracks }
    mpu401_send_data(trackmask);
    mpu401_send_command($B8);     { clear play counters }
    mpu401_send_command($0A);     { start play }
    if (debug) then writeln('done start_play');
end;

procedure mpu401_stop_play;
begin
    mpu401_send_command($05);
end;

procedure mpu401_handle_track_data_req(track_num: byte);
var
  this_len: byte;
  msg, meta: byte;
  meta_len: longint;
begin
  track_num:=m_playing.track_reverse_map[track_num];

  if (isr_debug) then writeln('track_data_req ', track_num);

  while true do begin;
    { Any time we send a reply, call `exit` to leave this function.
      Otherwise, we will keep looping
    }
    with m_playing.tracks[track_num] do begin
        if (play_count >= length) then begin
            complete:=true;
        end;
        if (complete)  then begin
            if (isr_debug) then writeln('send FC');
            mpu401_send_data(0);    { zero timing byte }
            mpu401_send_data($FC);  { end of track }
            exit; { RETURN }
        end;
        if (delta_left = NO_DELTA_LEFT) then begin
            scan_varint(play_ptr, this_len, delta_left);
            play_count:=play_count+this_len;
            if (isr_debug) then writeln('delta ', delta_left);
        end;
        if (delta_left>=240) then begin
            mpu401_send_data($F8);  { timing overflow; come back in 240 ticks }
            delta_left:=delta_left - 240;
            if (isr_debug) then writeln('sent F8 delta_left=', delta_left);
            exit; { RETURN }
        end;

        { it's time to read the next midi message }

        msg:=play_ptr^;
        inc(play_ptr);
        inc(play_count);

        if (isr_debug) then writeln('msg  ',msg);

        if (msg<=$7F) then begin
            { running status }
            if (isr_debug) then writeln('running status');
            msg:=last_msg;
            { put back the byte we read, so we can process as normal }
            dec(play_ptr);
            dec(play_count);
        end;

        last_msg:=msg;

        if (msg>=$80) and (msg<$F0) then begin
            mpu401_send_data(delta_left);  { send the timing byte }
            delta_left:=NO_DELTA_LEFT;
            mpu401_send_data(m_playing.track_voice_map[msg]);
            mpu401_send_data(play_ptr^);
            inc(play_ptr);
            inc(play_count);
            if (msg<$C0) or (msg>=$E0) then begin
                { any thing not Cx or Dx is a two-byte message }
                mpu401_send_data(play_ptr^);
                inc(play_ptr);
                inc(play_count);
            end;
            if (isr_debug) then writeln('send voice ');
            exit; { RETURN }
        end else if (msg=$FF) then begin { meta }
            meta:=play_ptr^;
            if (isr_debug) then writeln('meta ', meta);
            inc(play_ptr);
            inc(play_count);
            scan_varint(play_ptr, this_len, meta_len);
            play_count:=play_count+this_len;
            play_count:=play_count+meta_len;
            inc(play_ptr, meta_len);
            if (isr_debug) then writeln('meta_len ', meta_len);

            if (meta = $2F) then begin
                { end of track }
                if (isr_debug) then writeln('send FC due to 2F');
                mpu401_send_data(delta_left);
                delta_left:=NO_DELTA_LEFT;
                mpu401_send_data($FC);
                exit; { RETURN }
            end else begin
                if (isr_debug) then writeln('skip meta');
                delta_left:=NO_DELTA_LEFT;
                { ignore the meta, and loop around }
            end;
        end else begin
            { uh oh! }
        end;
    end;
  end;
end;

procedure mpu401_handle_data(b: byte);
begin
    if (b>=$F0) and (b<=$F7) then begin
        mpu401_handle_track_data_req(b-$F0);
    end;
end;

procedure mpu401_play_file(var m: TMidiFile);
var
    i: integer;
begin
    for i:=0 to (MAX_TRACK-1) do begin
       m.tracks[i].play_ptr:=m.tracks[i].raw;
       m.tracks[i].play_count:=0;
       m.tracks[i].delta_left:=NO_DELTA_LEFT;
    end;
    m_playing:=m;
    { now, start the mpu-401 }
    mpu401_start_play($FF, m.division);
end;

function mpu401_idle: boolean;
var
    i: integer;
begin
    for i:=1 to MAX_TRACK-1 do begin
        with m_playing.tracks[i] do begin
            if (length>0) and (not complete) then begin
                mpu401_idle:=false;
                exit;
            end;
        end;
    end;
    mpu401_idle := true;
end;

{$F+}
procedure mpu401_isr; interrupt;
var
    b: byte;
begin
{    disable_int;}
    if (isr_debug) then writeln('ISR');
    while (port[stat_port] and DSR)=0 do begin
        b:=port[data_port];
        if (isr_debug) then writeln('ISR DATA ', b);
        mpu401_handle_data(b);
    end;
{    enable_int;}
    { tell the 8259 we have completed our ISR }
    port[$A0] := $20;
    port[$20] := $20;
end;
{$F-}

procedure background_exithandler; far;
begin;
  ExitProc := old_exitproc;
  if old_intvec <> NIL then begin;
      writeln('Terminating ISR');
      setintvec(vec, old_intvec);
      old_intvec:=NIL;
  end;
end;

procedure mpu401_init(aport: word; anirq: word; install_isr: boolean);
var
    junk: byte;
begin
    stat_port:=aport+1; { verify! }
    com_port:=aport+1; { verify! }
    data_port:=aport;
    irq:=anirq;

    if (irq = 9) then begin
        vec:=$71;
    end else begin
        writeln('bad irq setting');
        halt;
    end;

    old_intvec:=NIL;
    old_exitproc:=ExitProc;

    if (install_isr) then begin
        if (debug) then writeln('set exitproc');
        ExitProc:=@background_exithandler;
        GetIntVec(vec, old_intvec);
        if (debug) then writeln('set int vec');
        SetIntVec(vec, @mpu401_isr);
    end;

    mpu401_send_command($FF); { reset }
    delay(100);
    junk := port[data_port];

    if (debug) then writeln('init complete');
end;

procedure mpu401_polling;
var
    b: byte;
begin
    while true do begin
        b:=mpu401_get_data;
        mpu401_handle_data(b);
    end;
end;

begin
    debug:=true;
    isr_debug:=false;
    old_exitproc:=NIL;
    old_intvec:=NIL;
end.