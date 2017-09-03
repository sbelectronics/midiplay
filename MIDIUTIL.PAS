unit midiutil;

interface

uses midifile;

function hex(b: byte): string;
procedure scan_varint(var p: Pbyte; var count: byte; var dest: longint);
procedure scan_3byte(var p: PByte; var val: longint);
procedure read_be_word(var f: file; var dest: word);
procedure read_be_longint(var f: file; var dest: longint);

function upstr(s: string): string;

implementation

function hex(b: byte): string;
const
    hexc: array[0..15] of char = '0123456789ABCDEF';
begin
    hex:=hexc[b shr 4] + hexc[b and $0F];
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

procedure scan_3byte(var p: PByte; var val: longint);
begin
    val:=p^;
    inc(p);
    val:=(val shl 8) + p^;
    inc(p);
    val:=(val shl 8) + p^;
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

function upstr(s: string): string;
var
    i: integer;
begin
    for i:=1 to length(s) do s[i]:=upcase(s[i]);
    upstr:=s;
end;


end.