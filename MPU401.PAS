{
  MPU401 Intelligent Mode Interface

  Scott Baker
  http://www.smbaker.com/

  This unit implements an interface to the MPU401 in intelligent mode.
  Start by calling mpu401_init(). Then call mpu401_start_play().
  After that, the MPU-401 will send track data requests
      gotta write the ISR...
}

unit mpu401;

interface

const
    MPU401_DEFAULT_PORT = $300;
    MPU401_DEFAULT_IRQ = 9;

procedure mpu401_init(aport: word; anirq: word);

procedure mpu401_send_command(b: byte);
procedure mpu401_send_data(b: byte);
function mpu401_get_data: byte;

function mpu401_idle: boolean;
procedure mpu401_start_play(trackmask: byte);
procedure mpu401_stop_play;

implementation

var
    com_port, stat_port, data_port: word;
    irq: word;

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
         { call isr }
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

function mpu401_idle: boolean;
begin
    { figure out if we're idle -- this would be if we've sent
      $FC on all tracks
    }
    mpu401_idle := false;
end;

procedure mpu401_init(aport: word; anirq: word);
begin
    stat_port:=aport+1; { verify! }
    com_port:=aport+1; { verify! }
    data_port:=aport;
    irq:=anirq;
end;

end.