unit PE.Parser.ImportDelayed;

interface

uses
  System.Generics.Collections,
  System.SysUtils,

  PE.Common,
  PE.Types,
  PE.Types.Directories,
  PE.Types.FileHeader, // expand TPEImage.Is32bit
  PE.Types.Imports,
  PE.Types.ImportsDelayed,
  PE.Utils;

type
  TPEImportDelayedParser = class(TPEParser)
  public
    function Parse: TParserResult; override;
  end;

implementation

uses
  PE.Image,
  PE.Imports.Func;

type
  TFuncs = TList<TPEImportFunctionDelayed>;

procedure ParseTable(
  const PE: TPEImage;
  const Table: TDelayLoadDirectoryTable;
  const Funcs: TFuncs);
var
  DllName: string;
  FnName: string;
  Fn: TPEImportFunctionDelayed;
  HintNameRva: TRVA;
  Ilt: TImportLookupTable;
  iFunc: integer;
  wordSize: integer;
var
  Ordinal: UInt16;
  Hint: UInt16 absolute Ordinal;
  Iat: TRVA;
begin
  PE.SeekRVA(Table.Name);
  DllName := PE.ReadANSIString;

  wordSize := PE.ImageWordSize;
  iFunc := 0;
  Iat := Table.DelayImportAddressTable;

  while PE.SeekRVA(Table.DelayImportNameTable + iFunc * wordSize) do
  begin
    HintNameRva := PE.ReadWord();
    if HintNameRva = 0 then
      break;

    Ilt.Create(HintNameRva, PE.Is32bit);

    Ordinal := 0;
    FnName := '';

    if Ilt.IsImportByOrdinal then
      // Import by ordinal only. No hint/name.
      Ordinal := Ilt.OrdinalNumber
    else
    begin
      // Import by name. Get hint/name
      if not PE.SeekRVA(HintNameRva) then
        raise Exception.Create('Error reading delayed import hint/name.');
      Hint := PE.ReadWord(2);
      FnName := PE.ReadANSIString;
    end;

    Fn := TPEImportFunctionDelayed.Create(Iat, FnName, Ordinal);
    PE.ImportsDelayed.AddNew(Iat, DllName, Fn);

    inc(Iat, wordSize);
    inc(iFunc);
  end;
end;

function TPEImportDelayedParser.Parse: TParserResult;
var
  PE: TPEImage;
  ddir: TImageDataDirectory;
  Table: TDelayLoadDirectoryTable;
  Tables: TList<TDelayLoadDirectoryTable>;
  Funcs: TFuncs;
begin
  PE := TPEImage(FPE);

  Result := PR_ERROR;

  // If no imports, it's ok.
  if not PE.DataDirectories.Get(DDIR_DELAYIMPORT, @ddir) then
    Exit(PR_OK);
  if ddir.IsEmpty then
    Exit(PR_OK);

  // Seek import dir.
  if not PE.SeekRVA(ddir.VirtualAddress) then
    Exit;

  Tables := TList<TDelayLoadDirectoryTable>.Create;
  try

    // Delay-load dir. table.
    while PE.ReadEx(Table, SizeOf(Table)) and (not Table.IsEmpty) do
      Tables.Add(Table);

    if Tables.Count = 0 then
      Exit;

    Funcs := TFuncs.Create;
    try
      for Table in Tables do
        ParseTable(PE, Table, Funcs);
    finally
      Funcs.Free;
    end;

    Result := PR_OK;
  finally
    Tables.Free;
  end;
end;

end.