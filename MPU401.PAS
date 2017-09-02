unit mpu401;

interface

procedure mpu401_init(aport: word; anirq: word);

procedure mpu401_send_command(b: byte);
procedure mpu401_send_data(b: byte);
function mpu401_get_data: byte;

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

procedure mpu401_init(aport: word; anirq: word);
begin
    stat_port:=aport;
    com_port:=aport+1; { verify! }
    data_port:=aport+1;  { verify! }
    irq:=anirq;
end;

end.