unit FirefoxCrypto;

interface

uses
  System.SysUtils,System.Classes,System.IniFiles,System.JSON,System.IOUtils,
  System.Win.Registry,System.Math,System.StrUtils,System.NetEncoding,
  Winapi.Windows,Uni,SQLiteUniProvider,DECCipherBase,DECCipherModes,
  DECCipherFormats,DECCiphers,DECFormat,DECHash;

const
  ASN1_INTEGER = $02;
  ASN1_OCTETSTRING = $04;
  ASN1_OBJECT_ID = $06;
  ASN1_SEQUENCE = $30;

type
  EASN1Error = class(Exception);
  EMasterKeyError = class(Exception);

  IASN1PBE = interface
    ['{A8F43B2E-9C74-4D23-B6A8-1234567890AB}']
    function Decrypt(const GlobalSalt: TBytes): TBytes;
    function Encrypt(const GlobalSalt, PlainText: TBytes): TBytes;
  end;

  TKeyIVPair = record
    Key: TBytes;
    IV: TBytes;
  end;

  TASN1Reader = class
  private
    FData: TBytes;
    FPosition: Integer;
    function ReadTag: Byte;
    function ReadLength: Integer;
    function ReadValue(Length: Integer): TBytes;
    function ReadInteger: Integer;
    function ReadOctetString: TBytes;
    function ReadObjectIdentifier: TBytes;
    procedure ReadSequence(out SeqLength: Integer);
  public
    constructor Create(const Data: TBytes);
  end;

  TNssPBE = class(TInterfacedObject, IASN1PBE)
  private
    FEntrySalt: TBytes;
    FLen: Integer;
    FEncrypted: TBytes;
    function DeriveKeyAndIV(const GlobalSalt: TBytes): TKeyIVPair;
  public
    constructor Create(const Data: TBytes);
    function Decrypt(const GlobalSalt: TBytes): TBytes;
    function Encrypt(const GlobalSalt, PlainText: TBytes): TBytes;
  end;

  TMetaPBE = class(TInterfacedObject, IASN1PBE)
  private
    FEntrySalt: TBytes;
    FIterationCount: Integer;
    FKeySize: Integer;
    FIV: TBytes;
    FEncrypted: TBytes;
    function DeriveKeyAndIV(const GlobalSalt: TBytes): TKeyIVPair;
  public
    constructor Create(const Data: TBytes);
    function Decrypt(const GlobalSalt: TBytes): TBytes;
    function Encrypt(const GlobalSalt, PlainText: TBytes): TBytes;
  end;

  TLoginPBE = class(TInterfacedObject, IASN1PBE)
  private
    FCipherText: TBytes;
    FIV: TBytes;
    FEncrypted: TBytes;
    function DeriveKeyAndIV(const GlobalSalt: TBytes): TKeyIVPair;
  public
    constructor Create(const Data: TBytes);
    function Decrypt(const GlobalSalt: TBytes): TBytes;
    function Encrypt(const GlobalSalt, PlainText: TBytes): TBytes;
  end;

function NewASN1PBE(const Data: TBytes): IASN1PBE;
function ProcessMasterKey(const MetaItem1, MetaItem2, NssA11, NssA102: TBytes): TBytes;

type
  TMasterKeyHelper = class
  private
    FProfilePath: string;
    FSQLiteConnection: TUniConnection;
    FGlobalSalt: TBytes;
  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetMasterKey: TBytes;
    property GlobalSalt: TBytes read FGlobalSalt;
  end;

implementation

function PKCS5UnPadding(Data: TBytes): TBytes;
var
  padding: Integer;
begin
  if Length(Data) = 0 then
    Exit(Data);
  padding := Data[Length(Data) - 1];
  if padding > Length(Data) then
    Exit(Data);
  SetLength(Result, Length(Data) - padding);
  Move(Data[0], Result[0], Length(Result));
end;

function PaddingZero(const Data: TBytes; Size: Integer): TBytes;
begin
  SetLength(Result, Size);
  FillChar(Result[0], Size, 0);
  if Length(Data) > 0 then
    Move(Data[0], Result[0], Min(Length(Data), Size));
end;

{ TASN1Reader }

constructor TASN1Reader.Create(const Data: TBytes);
begin
  inherited Create;
  FData := Data;
  FPosition := 0;
end;

function TASN1Reader.ReadTag: Byte;
begin
  if FPosition >= Length(FData) then
    raise EASN1Error.Create('Unexpected end of data reading tag');
  Result := FData[FPosition];
  Inc(FPosition);
end;

function TASN1Reader.ReadLength: Integer;
var
  B: Byte;
  ByteCount: Integer;
begin
  if FPosition >= Length(FData) then
    raise EASN1Error.Create('Unexpected end of data reading length');

  B := FData[FPosition];
  Inc(FPosition);

  if B < $80 then
    Exit(B);

  ByteCount := B and $7F;
  Result := 0;

  for var i := 0 to ByteCount - 1 do
  begin
    if FPosition >= Length(FData) then
      raise EASN1Error.Create('Unexpected end of data reading length bytes');
    Result := (Result shl 8) or FData[FPosition];
    Inc(FPosition);
  end;
end;

function TASN1Reader.ReadValue(Length: Integer): TBytes;
begin
  if FPosition + Length > System.Length(FData) then
    raise EASN1Error.Create('Unexpected end of data reading value');

  SetLength(Result, Length);
  if Length > 0 then
  begin
    Move(FData[FPosition], Result[0], Length);
    Inc(FPosition, Length);
  end;
end;

function TASN1Reader.ReadInteger: Integer;
var
  Value: TBytes;
begin
  if ReadTag <> ASN1_INTEGER then
    raise EASN1Error.Create('Expected INTEGER tag');

  Value := ReadValue(ReadLength);
  if Length(Value) = 1 then
    Result := Value[0]
  else
  begin
    Result := 0;
    for var i := 0 to Length(Value) - 1 do
      Result := (Result shl 8) or Value[i];
  end;
end;

function TASN1Reader.ReadOctetString: TBytes;
begin
  if ReadTag <> ASN1_OCTETSTRING then
    raise EASN1Error.Create('Expected OCTET STRING tag');
  Result := ReadValue(ReadLength);
end;

function TASN1Reader.ReadObjectIdentifier: TBytes;
begin
  if ReadTag <> ASN1_OBJECT_ID then
    raise EASN1Error.Create('Expected OBJECT IDENTIFIER tag');
  Result := ReadValue(ReadLength);
end;

procedure TASN1Reader.ReadSequence(out SeqLength: Integer);
begin
  if ReadTag <> ASN1_SEQUENCE then
    raise EASN1Error.Create('Expected SEQUENCE tag');
  SeqLength := ReadLength;
end;

{ TNssPBE }

constructor TNssPBE.Create(const Data: TBytes);
var
  Reader: TASN1Reader;
  SeqLength: Integer;
begin
  inherited Create;
  Reader := TASN1Reader.Create(Data);
  try
    Reader.ReadSequence(SeqLength);
    Reader.ReadSequence(SeqLength);
    Reader.ReadObjectIdentifier; // Skip OID
    Reader.ReadSequence(SeqLength);
    FEntrySalt := Reader.ReadOctetString;
    FLen := Reader.ReadInteger;
    FEncrypted := Reader.ReadOctetString;
  finally
    Reader.Free;
  end;
end;

function TNssPBE.DeriveKeyAndIV(const GlobalSalt: TBytes): TKeyIVPair;
var
  Hash: THash_SHA1;
  Salt, HashPrefix, CompositeHash, PaddedSalt: TBytes;
  HmacResult, KeyComp1, KeyComp2, CombinedKey: TBytes;
begin
  Hash := THash_SHA1.Create;
  try
    Salt := FEntrySalt;
    HashPrefix := Hash.CalcBytes(GlobalSalt);

    SetLength(CompositeHash, Length(HashPrefix) + Length(Salt));
    Move(HashPrefix[0], CompositeHash[0], Length(HashPrefix));
    Move(Salt[0], CompositeHash[Length(HashPrefix)], Length(Salt));
    CompositeHash := Hash.CalcBytes(CompositeHash);

    PaddedSalt := PaddingZero(Salt, 20);
    HmacResult := Hash.HMAC(PaddedSalt, CompositeHash);

    // Generate key components
    KeyComp1 := Hash.HMAC(PaddedSalt + Salt, CompositeHash);
    KeyComp2 := Hash.HMAC(HmacResult + Salt, CompositeHash);

    // Combine key components
    SetLength(CombinedKey, Length(KeyComp1) + Length(KeyComp2));
    Move(KeyComp1[0], CombinedKey[0], Length(KeyComp1));
    Move(KeyComp2[0], CombinedKey[Length(KeyComp1)], Length(KeyComp2));

    // Extract key and IV
    SetLength(Result.Key, 24);
    Move(CombinedKey[0], Result.Key[0], 24);

    SetLength(Result.IV, 8);
    Move(CombinedKey[Length(CombinedKey) - 8], Result.IV[0], 8);
  finally
    Hash.Free;
  end;
end;

function TNssPBE.Decrypt(const GlobalSalt: TBytes): TBytes;
var
  KeyIV: TKeyIVPair;
  Cipher: TCipher_3DES;
begin
  KeyIV := DeriveKeyAndIV(GlobalSalt);
  Cipher := TCipher_3DES.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(KeyIV.Key, KeyIV.IV);
    Result := PKCS5UnPadding(Cipher.DecodeBytes(FEncrypted));
  finally
    Cipher.Free;
  end;
end;

function TNssPBE.Encrypt(const GlobalSalt, PlainText: TBytes): TBytes;
var
  KeyIV: TKeyIVPair;
  Cipher: TCipher_3DES;
begin
  KeyIV := DeriveKeyAndIV(GlobalSalt);
  Cipher := TCipher_3DES.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(KeyIV.Key, KeyIV.IV);
    Result := Cipher.EncodeBytes(PlainText);
  finally
    Cipher.Free;
  end;
end;

{ TMetaPBE }

constructor TMetaPBE.Create(const Data: TBytes);
var
  Reader: TASN1Reader;
  SeqLength: Integer;
begin
  inherited Create;
  Reader := TASN1Reader.Create(Data);
  try
    Reader.ReadSequence(SeqLength);
    Reader.ReadSequence(SeqLength);
    Reader.ReadObjectIdentifier; // Skip OID
    Reader.ReadSequence(SeqLength);
    Reader.ReadSequence(SeqLength);
    Reader.ReadObjectIdentifier; // Skip OID
    Reader.ReadSequence(SeqLength);
    FEntrySalt := Reader.ReadOctetString;
    FIterationCount := Reader.ReadInteger;
    FKeySize := Reader.ReadInteger;
    Reader.ReadSequence(SeqLength);
    Reader.ReadObjectIdentifier; // Skip Algorithm OID
    Reader.ReadSequence(SeqLength);
    Reader.ReadObjectIdentifier; // Skip IV OID
    FIV := Reader.ReadOctetString;
    FEncrypted := Reader.ReadOctetString;
  finally
    Reader.Free;
  end;
end;

function TMetaPBE.DeriveKeyAndIV(const GlobalSalt: TBytes): TKeyIVPair;
var
  Hash: THash_SHA1;
  Password: TBytes;
begin
  Hash := THash_SHA1.Create;
  try
    Password := Hash.CalcBytes(GlobalSalt);
    Result.Key := THash_SHA256.PBKDF2(Password, FEntrySalt, FIterationCount, FKeySize);
    SetLength(Result.IV, 16);
    Result.IV[0] := 4;
    Result.IV[1] := 14;
    Move(FIV[0], Result.IV[2], Min(14, Length(FIV)));
  finally
    Hash.Free;
  end;
end;

function TMetaPBE.Decrypt(const GlobalSalt: TBytes): TBytes;
var
  KeyIV: TKeyIVPair;
  Cipher: TCipher_AES256;
begin
  KeyIV := DeriveKeyAndIV(GlobalSalt);
  Cipher := TCipher_AES256.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(KeyIV.Key, KeyIV.IV);
    Result := PKCS5UnPadding(Cipher.DecodeBytes(FEncrypted));
  finally
    Cipher.Free;
  end;
end;

function TMetaPBE.Encrypt(const GlobalSalt, PlainText: TBytes): TBytes;
var
  KeyIV: TKeyIVPair;
  Cipher: TCipher_AES256;
begin
  KeyIV := DeriveKeyAndIV(GlobalSalt);
  Cipher := TCipher_AES256.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(KeyIV.Key, KeyIV.IV);
    Result := Cipher.EncodeBytes(PlainText);
  finally
    Cipher.Free;
  end;
end;

{ TLoginPBE }

constructor TLoginPBE.Create(const Data: TBytes);
var
  Reader: TASN1Reader;
  SeqLength: Integer;
begin
  inherited Create;
  Reader := TASN1Reader.Create(Data);
  try
    Reader.ReadSequence(SeqLength);
    FCipherText := Reader.ReadOctetString;
    Reader.ReadSequence(SeqLength);
    Reader.ReadObjectIdentifier; // Skip OID
    FIV := Reader.ReadOctetString;
    FEncrypted := Reader.ReadOctetString;
  finally
    Reader.Free;
  end;
end;

function TLoginPBE.DeriveKeyAndIV(const GlobalSalt: TBytes): TKeyIVPair;
begin
  Result.Key := GlobalSalt;
  Result.IV := FIV;
end;

function TLoginPBE.Decrypt(const GlobalSalt: TBytes): TBytes;
var
  KeyIV: TKeyIVPair;
  Cipher: TCipher_3DES;
begin
  KeyIV := DeriveKeyAndIV(GlobalSalt);
  Cipher := TCipher_3DES.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(KeyIV.Key, KeyIV.IV);
    Result := PKCS5UnPadding(Cipher.DecodeBytes(FEncrypted));
  finally
    Cipher.Free;
  end;
end;

function TLoginPBE.Encrypt(const GlobalSalt, PlainText: TBytes): TBytes;
var
  KeyIV: TKeyIVPair;
  Cipher: TCipher_3DES;
begin
  KeyIV := DeriveKeyAndIV(GlobalSalt);
  Cipher := TCipher_3DES.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(KeyIV.Key, KeyIV.IV);
    Result := Cipher.EncodeBytes(PlainText);
  finally
    Cipher.Free;
  end;
end;

function NewASN1PBE(const Data: TBytes): IASN1PBE;
begin
  try
    Result := TNssPBE.Create(Data);
    Exit;
  except
    // Continue to next type
  end;

  try
    Result := TMetaPBE.Create(Data);
    Exit;
  except
    // Continue to next type
  end;

  try
    Result := TLoginPBE.Create(Data);
    Exit;
  except
    // Continue to next type
  end;

  raise EASN1Error.Create('Failed to decode ASN1 data');
end;

function ProcessMasterKey(const MetaItem1, MetaItem2, NssA11, NssA102: TBytes): TBytes;
const
  PASSWORD_CHECK = 'password-check';
  EXPECTED_KEY: array[0..15] of Byte = (
    $F8, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $01
  );
var
  MetaPBE, NssA11PBE: IASN1PBE;
  Flag, FinallyKey: TBytes;
  PasswordCheckBytes: TBytes;
begin
  try
    // Create and decrypt MetaPBE
    MetaPBE := NewASN1PBE(MetaItem2);
    Flag := MetaPBE.Decrypt(MetaItem1);

    // Verify password-check flag
    PasswordCheckBytes := TEncoding.UTF8.GetBytes(PASSWORD_CHECK);
    if Pos(PAnsiChar(PasswordCheckBytes), PAnsiChar(Flag)) = 0 then
      raise EMasterKeyError.Create('Flag verification failed: password-check not found');

    // Verify NssA102
    if not CompareMem(@NssA102[0], @EXPECTED_KEY[0], Length(EXPECTED_KEY)) then
      raise EMasterKeyError.Create('Master key verification failed: NssA102 not equal to expected value');

    // Create and decrypt NssA11PBE
    NssA11PBE := NewASN1PBE(NssA11);
    FinallyKey := NssA11PBE.Decrypt(MetaItem1);

    // Verify key length
    if Length(FinallyKey) < 24 then
      raise EMasterKeyError.Create('Length of final key is less than 24 bytes');

    // Return first 24 bytes
    SetLength(Result, 24);
    Move(FinallyKey[0], Result[0], 24);

    // Debug output - convert to hex string
    var HexStr := '';
    for var I := 0 to 23 do
      HexStr := HexStr + IntToHex(Result[I], 2);

  except
    on E: Exception do
      raise EMasterKeyError.CreateFmt('Process master key error: %s', [E.Message]);
  end;
end;

{ TMasterKeyHelper }

constructor TMasterKeyHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
end;

destructor TMasterKeyHelper.Destroy;
begin
  FSQLiteConnection.Free;
  inherited;
end;

function TMasterKeyHelper.GetMasterKey: TBytes;
var
  Query: TUniQuery;
  MetaItem1, MetaItem2, NSSA11, NSSA102: TBytes;
begin
  FSQLiteConnection.Database := TPath.Combine(FProfilePath, 'key4.db');
  try
    FSQLiteConnection.Connect;

    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;

      // Get metadata items
      Query.SQL.Text := 'SELECT CAST(item1 as BLOB) as item1, CAST(item2 as BLOB) as item2 ' +
                       'FROM metaData WHERE id = "password"';
      Query.Open;
      if not Query.IsEmpty then
      begin
        MetaItem1 := Query.FieldByName('item1').AsBytes;
        FGlobalSalt := MetaItem1; // Store GlobalSalt
        MetaItem2 := Query.FieldByName('item2').AsBytes;
      end
      else
        WriteLn('Debug: No metadata found');

      // Get NSS items
      Query.SQL.Text := 'SELECT CAST(a11 as BLOB) as a11, CAST(a102 as BLOB) as a102 ' +
                       'FROM nssPrivate';
      Query.Open;
      if not Query.IsEmpty then
      begin
        NSSA11 := Query.FieldByName('a11').AsBytes;
        NSSA102 := Query.FieldByName('a102').AsBytes;
      end
      else
        WriteLn('Debug: No NSS items found');

      Result := ProcessMasterKey(MetaItem1, MetaItem2, NSSA11, NSSA102);
    except
      on E: Exception do
      begin
        WriteLn(Format('Debug: Error in GetMasterKey: %s', [E.Message]));
        raise;
      end;
    end;
  finally
    Query.Free;
  end;
end;


end.

