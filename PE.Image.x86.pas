{
  *
  * Class for X86, X86-64 specifics.
  *
}
unit PE.Image.x86;

interface

uses
  System.Generics.Collections,
  PE.Common,
  PE.Image,
  PE.Section;

type
  TPEImageX86 = class(TPEImage)
  protected
    // Find relative jump or call in section, e.g e8,x,x,x,x or e9,x,x,x,x.
    // List must be created before passing it to the function.
    // Found VAs will be appended to list.
    function FindRelativeJumpInternal(
      const Sec: TPESection;
      ByteOpcode: Byte;
      TargetVA: TVA;
      const List: TList<TVA>): Boolean;
  public
    function FindRelativeJump(
      const Sec: TPESection;
      TargetVA: TVA;
      const List: TList<TVA>): Boolean;

    function FindRelativeCall(
      const Sec: TPESection;
      TargetVA: TVA;
      const List: TList<TVA>): Boolean;

    // Fill Count bytes at VA with nops (0x90).
    // Result is number of nops written.
    function Nop(VA: TVA; Count: integer = 1): UInt32;

    // Nop range.
    // BeginVA: inclusive
    // EndVA: exclusive
    function NopRange(BeginVA, EndVA: TVA): UInt32; inline;

    // Nop Call or Jump.
    function NopCallOrJump(VA: TVA): Boolean;

    // Write call or jump, like:
    // E8/E9 xx xx xx xx
    // IsCall: True - call, False - jump.
    function WriteRelCallOrJump(SrcVA, DstVA: TVA; IsCall: Boolean): Boolean;
  end;

implementation

const
  OPCODE_NOP      = $90;
  OPCODE_CALL_REL = $E8;
  OPCODE_JUMP_REL = $E9;

  { TPEImageX86 }

function TPEImageX86.FindRelativeCall(
  const Sec: TPESection;
  TargetVA: TVA;
  const List: TList<TVA>): Boolean;
begin
  Result := FindRelativeJumpInternal(Sec, OPCODE_CALL_REL, TargetVA, List);
end;

function TPEImageX86.FindRelativeJump(
  const Sec: TPESection;
  TargetVA: TVA;
  const List: TList<TVA>): Boolean;
begin
  Result := FindRelativeJumpInternal(Sec, OPCODE_JUMP_REL, TargetVA, List);
end;

function TPEImageX86.FindRelativeJumpInternal(
  const Sec: TPESection;
  ByteOpcode: Byte;
  TargetVA: TVA;
  const List: TList<TVA>): Boolean;
var
  curVa, va0, va1, tstVa: TVA;
  delta: int32;
  opc: Byte;
begin
  Result := False;

  va0 := RVAToVA(Sec.RVA);
  va1 := RVAToVA(Sec.GetEndRVA - SizeOf(ByteOpcode) - SizeOf(delta));

  if not SeekVA(va0) then
    exit(False);

  while self.PositionVA <= va1 do
  begin
    curVa := self.PositionVA;

    // get opcode
    if Read(@opc, SizeOf(ByteOpcode)) <> SizeOf(ByteOpcode) then
      exit;
    if opc = ByteOpcode then
    // on found probably jmp/call
    begin
      delta := int32(ReadUInt32);
      tstVa := curVa + SizeOf(ByteOpcode) + SizeOf(delta) + delta;
      if tstVa = TargetVA then
      begin // hit
        List.Add(curVa);
        Result := True; // at least 1 result is ok
      end
      else
      begin
        if not SeekVA(curVa + SizeOf(ByteOpcode)) then
          exit;
      end;
    end;
  end;
end;

function TPEImageX86.Nop(VA: TVA; Count: integer): UInt32;
begin
  Result := Sections.FillMemory(VAToRVA(VA), Count, OPCODE_NOP);
end;

function TPEImageX86.NopRange(BeginVA, EndVA: TVA): UInt32;
begin
  if EndVA > BeginVA then
    Result := Nop(BeginVA, EndVA - BeginVA)
  else
    Result := 0;
end;

function TPEImageX86.NopCallOrJump(VA: TVA): Boolean;
begin
  Result := Sections.FillMemoryEx(VAToRVA(VA), 5, True, OPCODE_NOP) = 5;
end;

function TPEImageX86.WriteRelCallOrJump(SrcVA, DstVA: TVA; IsCall: Boolean): Boolean;
type
  TJump = packed record
    Opcode: Byte;
    delta: integer;
  end;
var
  jmp: TJump;

begin
  if IsCall then
    jmp.Opcode := OPCODE_CALL_REL
  else
    jmp.Opcode := OPCODE_JUMP_REL;
  jmp.delta := DstVA - (SrcVA + SizeOf(TJump));
  self.PositionVA := SrcVA;
  Result := self.WriteEx(@jmp, SizeOf(TJump));
end;

end.
