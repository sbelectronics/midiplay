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

uses dos, midifile, midiutil;

const
    MPU401_DEFAULT_PORT = $300;
    MPU401_DEFAULT_IRQ = 9;

{ low-level operations }
procedure mpu401_init(aport: word; anirq: word);
procedure mpu401_send_command(b: byte);
procedure mpu401_send_data(b: byte);
function mpu401_get_data: byte;

{ intermediate operations }
procedure mpu401_start_play(trackmask: byte);
procedure mpu401_stop_play;

{ high-level operations }
procedure mpu401_play_file(var m: TMidiFile);
function mpu401_idle: boolean;

procedure mpu401_handle_data(b: byte);

implementation

var
    com_port, stat_port, data_port: word;
    irq: word;
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
  { poll for DRR (bit 6) to be 0 }
  while (port[stat_port] and 32)=32 do begin
  end;

  disable_int;

  port[com_port]:=b;

  { poll for DSR (bit 7) to be 0 }
  while (port[stat_port] and 64)=64 do begin
  end;

  repeat
     data:=port[data_port];
     if (data <> $FE) then begin
         mpu401_handle_data(data); { call isr }
     end;
  until (data = $FE);

  enable_int;
end;

procedure mpu401_send_data(b: byte);
begin
  { poll for DRR (bit 6) to be 0 }
  while (port[stat_port] and 32)=32 do begin
  end;

  port[data_port] := b;
end;

function mpu401_get_data: byte;
begin
  { poll for DSR (bit 7) to be 0 }
  while (port[stat_port] and 64)=64 do begin
  end;

  mpu401_get_data := port[data_port];
end;

procedure mpu401_start_play(trackmask: byte);
begin
    mpu401_send_command($EC);     { activate tracks }
    mpu401_send_data(trackmask);
    mpu401_send_command($B8);     { clear play counters }
    mpu401_send_command($0A);     { start play }
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
  while true do begin;
    { Any time we send a reply, call `exit` to leave this function.
      Otherwise, we will keep looping
    }
    with m_playing.tracks[track_num] do begin
        if (play_count >= length) then begin
            complete:=true;
        end;
        if (complete)  then begin
            mpu401_send_data($FC);  { end of track }
            exit; { RETURN }
        end;
        if (delta_left = NO_DELTA_LEFT) then begin
            scan_varint(play_ptr, this_len, delta_left);
            play_count:=play_count+this_len;
        end;
        if (delta_left>=240) then begin
            mpu401_send_data($F8);  { timing overflow; come back in 240 ticks }
            delta_left:=delta_left - 240;
            exit; { RETURN }
        end;

        { it's time to read the next midi message }

        msg:=play_ptr^;
        inc(play_ptr);
        inc(play_count);

        if (msg<=$7F) then begin
            { running status }
            mpu401_send_data(delta_left);  { send the timing byte }
            mpu401_send_data(msg);
            if (play_ptr^ <= $7F ) then begin
                mpu401_send_data(play_ptr^);
                inc(play_ptr);
                inc(play_count);
            end;
            exit; { RETURN }
        end else if (msg>=$80) and (msg<$F0) then begin
            mpu401_send_data(delta_left);  { send the timing byte }
            mpu401_send_data(msg);
            mpu401_send_data(play_ptr^);
            inc(play_ptr);
            inc(play_count);
            if (msg<$C0) or (msg>=$E0) then begin
                { any thing not Cx or Dx is a two-byte message }
                mpu401_send_data(play_ptr^);
                inc(play_ptr);
                inc(play_count);
            end;
            exit; { RETURN }
        end else if (msg=$FF) then begin { meta }
            meta:=play_ptr^;
            scan_varint(play_ptr, this_len, meta_len);
            play_count:=play_count+this_len;
            play_count:=play_count+meta_len;
            inc(play_ptr, meta_len);

            if (meta = $2F) then begin
                { end of track }
                mpu401_send_data($FC);
                exit; { RETURN }
            end else begin
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
    mpu401_start_play($FF);
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
    b:=mpu401_get_data;
    mpu401_handle_data(b);
end;
{$F-}

procedure background_exithandler; far;
begin;
  ExitProc := old_exitproc;
  if old_intvec <> NIL then begin;
      writeln('Terminating ISR');
      setintvec(irq, old_intvec);
      old_intvec:=NIL;
  end;
end;

procedure mpu401_init(aport: word; anirq: word);
begin
    stat_port:=aport+1; { verify! }
    com_port:=aport+1; { verify! }
    data_port:=aport;
    irq:=anirq;

    old_intvec:=NIL;
    old_exitproc:=ExitProc;
    ExitProc:=@background_exithandler;
    GetIntVec(irq, old_intvec);
    SetIntVec(irq, @mpu401_isr);
end;

begin
    old_exitproc:=NIL;
    old_intvec:=NIL;
end.