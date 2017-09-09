{
  MPU401 Intelligent Mode Interface

  Scott Baker
  http://www.smbaker.com/

  This unit implements an interface to the MPU401 in intelligent mode.
  Start by calling mpu401_init(). Then call mpu401_play_file().
  After that, the MPU-401 will send track data requests
      The ISR will handle the track data requests

  Tested under dropbox. See the readme to know what works and what
  does not.
}

unit mpu401;

interface

uses dos, crt, midifile, midiutil, midiopt;

const
    MPU401_DEFAULT_PORT = $330;
    MPU401_DEFAULT_IRQ = 9;
    DSR = 128;
    DRR = 64;
var
    opts: TMidiOptions;
    division_mul: byte;
    division_div: byte;

    { The ISR takes around 843 bytes of stack space due to the writeln
      statements (even if they're not executed!). So allocate a private
      stack for the ISR. 2K should be way more than is necessary.
    }

    isr_stack: array[1..2048] of byte;
    isr_stack_seg: word;
    isr_stack_ptr: word;
    save_stack_seg: word;
    save_stack_ptr: word;

{ low-level operations }
procedure mpu401_init(aport: word; anirq: word; var midi_opts: TMidiOptions);
procedure mpu401_send_command(b: byte);
procedure mpu401_send_data(b: byte);
function mpu401_get_data: byte;

{ intermediate operations }
procedure mpu401_start_play(trackmask: byte; division: word; enable_conductor: boolean);
procedure mpu401_stop_play;

{ high-level operations }
procedure mpu401_play_file(var m: TMidiFile);
function mpu401_idle: boolean;
function mpu401_done_playing: boolean;

{ ISR stuff }
procedure mpu401_handle_data(b: byte);
procedure mpu401_polling;

procedure stack_analysis;

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
  if (opts.debug) then writeln('send_command (', hex(b), '): wait for DRR');

  { poll for DRR (bit 6) to be 0 }
  while (port[stat_port] and DRR)=DRR do begin
  end;

  if (opts.debug) then writeln('send_command: DRR ready');

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

  if (opts.debug) then writeln('send_command: complete');
end;

procedure mpu401_send_data(b: byte);
begin
  { poll for DRR (bit 6) to be 0 }
  while (port[stat_port] and DRR)=DRR do begin
  end;

  if (opts.debug_isr) then writeln('send data ',hex(b));

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

function tempo_to_bpm(tempo: longint): byte;
begin
    tempo_to_bpm:=round(60000000/tempo);
end;

procedure mpu401_start_play(trackmask: byte; division: word; enable_conductor: boolean);
begin
    { hardcoding some divisions that aren't directly supported by the
      mpu-401... Probably ought to find a way to do this automatically.
    }
    division_div:=1;
    division_mul:=1;
    if (division = 48) then begin
        division_mul:=2;
        division:=96;
    end else if (division = 480) then begin
        division_div:=4;
        division:=120;
    end;

    if (opts.debug) then writeln('starting start_play');
    mpu401_send_command(division_to_timebase(division));
    mpu401_send_command($EC);     { activate tracks }
    mpu401_send_data(trackmask);
    if (enable_conductor) then begin
        mpu401_send_command($8F);
    end else begin
        mpu401_send_command($8E);
    end;
    mpu401_send_command($B8);     { clear play counters }
    mpu401_send_command($0A);     { start play }
    if (opts.debug) then writeln('done start_play');
end;

procedure mpu401_stop_play;
begin
    mpu401_send_command($05);
end;

procedure mpu401_handle_track_data_req(track_num: byte; conductor: boolean);
var
  this_len: byte;
  msg, meta: byte;
  meta_len: longint;
  meta_ptr: Pbyte;
  tempo: longint;
begin
  if (not conductor) then begin
      track_num:=m_playing.track_reverse_map[track_num];
  end;

  if (opts.debug_isr) then writeln('track_data_req ', track_num);

  while true do begin;
    { Any time we send a reply, call `exit` to leave this function.
      Otherwise, we will keep looping
    }
    with m_playing.tracks[track_num] do begin
        if (play_count >= length) then begin
            complete:=true;
        end;
        if (complete)  then begin
            if (opts.debug_isr) then writeln('send FC');
            mpu401_send_data(0);    { zero timing byte }
            mpu401_send_data($FC);  { end of track }
            exit; { RETURN }
        end;
        if (delta_left = NO_DELTA_LEFT) then begin
            scan_varint(play_ptr, this_len, delta_left);
            if (division_div <> 1) or (division_mul <> 1) then begin
                delta_left:=round(delta_left*division_mul/division_div);
            end;
            play_count:=play_count+this_len;
            if (opts.debug_isr) then writeln('delta ', delta_left);
        end;
        if (delta_left>=240) then begin
            mpu401_send_data($F8);  { timing overflow; come back in 240 ticks }
            delta_left:=delta_left - 240;
            if (opts.debug_isr) then writeln('sent F8 delta_left=', delta_left);
            exit; { RETURN }
        end;

        { it's time to read the next midi message }

        msg:=play_ptr^;
        inc(play_ptr);
        inc(play_count);

        if (opts.debug_isr) then writeln('msg  ',hex(msg));

        if (msg<=$7F) then begin
            { running status }
            if (opts.debug_isr) then writeln('running status');
            msg:=last_msg;
            { put back the byte we read, so we can process as normal }
            dec(play_ptr);
            dec(play_count);
        end;

        last_msg:=msg;

        if (msg>=$80) and (msg<$F0) then begin
            if (conductor) then begin
                { if conductor, ignore notes as there shouldn't be any }
                delta_left:=NO_DELTA_LEFT;
                inc(play_ptr);
                inc(play_count);
                if (msg<$C0) or (msg>=$E0) then begin
                    inc(play_ptr);
                    inc(play_count);
                end;
                if (opts.debug_isr) then writeln('ignore voice in conductor channel');
            end else begin;
                mpu401_send_data(delta_left);  { send the timing byte }
                delta_left:=NO_DELTA_LEFT;
                mpu401_send_data(m_playing.channel_msg_map[msg]);
                mpu401_send_data(play_ptr^);
                inc(play_ptr);
                inc(play_count);
                if (msg<$C0) or (msg>=$E0) then begin
                    { any thing not Cx or Dx is a two-byte message }
                    mpu401_send_data(play_ptr^);
                    inc(play_ptr);
                    inc(play_count);
                end;
                if (opts.debug_isr) then writeln('send voice ');
                exit; { RETURN }
            end;
        end else if (msg=$FF) then begin { meta }
            meta:=play_ptr^;
            if (opts.debug_isr) then writeln('meta ', hex(meta));
            inc(play_ptr);
            inc(play_count);
            scan_varint(play_ptr, this_len, meta_len);
            play_count:=play_count+this_len;
            play_count:=play_count+meta_len;
            meta_ptr:=play_ptr;
            inc(play_ptr, meta_len);
            if (opts.debug_isr) then writeln('meta_len ', meta_len);

            if (meta = $2F) then begin
                { end of track }
                if (opts.debug_isr) then writeln('send FC due to 2F');
                mpu401_send_data(delta_left);
                delta_left:=NO_DELTA_LEFT;
                mpu401_send_data($FC);
                exit; { RETURN }
            end else if (meta = $51) and conductor then begin
                { tempo change }
                scan_3byte(meta_ptr, tempo);
                mpu401_send_data(delta_left);
                mpu401_send_data($E0); { set tempo }
                mpu401_send_data(tempo_to_bpm(tempo));
                if (opts.debug_isr) then writeln('send tempo change to ', tempo_to_bpm(tempo));
                exit; { RETURN }
            end else begin
                if (opts.debug_isr) then writeln('skip meta');
                delta_left:=NO_DELTA_LEFT;
                { ignore the meta, and loop around }
            end;
        end else if (msg = $F0) then begin
            { sysex - ignore it }
            if (opts.debug_isr) then writeln('skip sysex');
            delta_left:=NO_DELTA_LEFT;
            while (play_ptr^ <> $F7) do begin
                inc(play_ptr);
                inc(play_count);
            end;
            inc(play_ptr);
            inc(play_count);
        end else begin
            { uh oh! }
            writeln('ERROR: encountered bad msg byte ', hex(msg));
        end;
    end;
  end;
end;

procedure mpu401_handle_data(b: byte);
begin
    if (b>=$F0) and (b<=$F7) then begin
        mpu401_handle_track_data_req(b-$F0, false); { voice track }
    end else if (b=$F9) then begin
        mpu401_handle_track_data_req(m_playing.conductor_track_num, true); { conductor }
    end else if (b=$FC) then begin
        if (opts.debug_isr) then writeln('FC All  End Received');
        m_playing.done_playing:=true;
    end else begin
        writeln('ERROR: bad byte in handle_data ', hex(b));
    end;
end;

procedure mpu401_play_file(var m: TMidiFile);
var
    i: integer;
    enable_conductor: boolean;
begin
    for i:=0 to (MAX_TRACK-1) do begin
       m.tracks[i].play_ptr:=m.tracks[i].raw;
       m.tracks[i].play_count:=0;
       m.tracks[i].delta_left:=NO_DELTA_LEFT;
    end;
    m.done_playing:=false;
    m_playing:=m;
    { now, start the mpu-401 }
    mpu401_start_play($FF, m.division, m.enable_conductor);
end;

function mpu401_done_playing: boolean;
begin
    mpu401_done_playing:=m_playing.done_playing;
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

procedure mpu401_isr;
var
    b: byte;
begin
    if (opts.debug_isr) then writeln('ISR');
    while (port[stat_port] and DSR)=0 do begin
        b:=port[data_port];
        if (opts.debug_isr) then writeln('ISR DATA ', hex(b));
        mpu401_handle_data(b);
    end;
end;

{$F+}
procedure mpu401_isr_wrapper; interrupt;
begin
    { wrap the ISR with a private stack }
    asm
       cli
       mov save_stack_seg, SS
       mov save_stack_ptr, SP
       mov SS, isr_stack_seg
       mov SP, isr_stack_ptr
       sti
    end;
    mpu401_isr;
    asm
       cli
       mov SS, save_stack_seg;
       mov SP, save_stack_ptr;
       sti
    end;
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

procedure mpu401_init(aport: word; anirq: word; var midi_opts: TMidiOptions);
var
    junk: byte;
begin
    opts:=midi_opts;

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

    if (not opts.polling) then begin
        if (opts.debug) then writeln('set exitproc');
        ExitProc:=@background_exithandler;
        GetIntVec(vec, old_intvec);
        if (opts.debug) then writeln('set int vec');
        SetIntVec(vec, @mpu401_isr_wrapper);
    end;

    if (opts.reset) then begin
        mpu401_send_command($FF); { reset }
        delay(100);
    end;
    junk := port[data_port];

    if (opts.debug) then writeln('init complete');
end;

procedure mpu401_polling;
var
    b: byte;
begin
    while true do begin
        b:=mpu401_get_data;
        mpu401_handle_data(b);
        if mpu401_done_playing then begin
            writeln('Song Complete.');
            exit;
        end;
        if keypressed then begin
            exit;
        end;
    end;
end;

procedure stack_analysis;
var
   i: integer;
begin
    for i := 1 to sizeof(isr_stack) do begin
        if isr_stack[i] <> $F3 then begin
            writeln('stack used ', sizeof(isr_stack)-i+1);
            exit;
        end;
    end;
end;

begin
    { Setup the private stack. Fill it with some random byte (F3) so we
      can analyze it for consumption later if we want to. Stack operations
      are decrement and then write, so we could point to the very end, but
      I set the pointer 8 in from the end, just to be safe.
    }
    fillchar(isr_stack, sizeof(isr_stack), $F3);
    isr_stack_seg:=seg(isr_stack[sizeof(isr_stack)-8]);
    isr_stack_ptr:=ofs(isr_stack[sizeof(isr_stack)-8]);

    set_default_options(opts);

    old_exitproc:=NIL;
    old_intvec:=NIL;
end.