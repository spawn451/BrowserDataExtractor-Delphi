unit ChromiumCookie;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults, System.DateUtils, System.JSON, System.StrUtils,
  Winapi.Windows, Uni, SQLiteUniProvider, ChromiumCrypto;

type

  TBrowserKind = (bkChrome, bkBrave, bkEdge);

  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TCookieItem = record
    Host: string;
    Path: string;
    KeyName: string;
    Value: string;
    IsSecure: Boolean;
    IsHTTPOnly: Boolean;
    HasExpire: Boolean;
    IsPersistent: Boolean;
    CreateDate: TDateTime;
    ExpireDate: TDateTime;
  end;

  TCookieItems = TArray<TCookieItem>;

  TChromiumCookieHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FBrowserKind: TBrowserKind;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_CHROMIUM_COOKIE = 'SELECT name, encrypted_value, host_key, path, ' +
      'strftime(''%Y-%m-%d %H:%M:%S'', creation_utc/1000000, ''unixepoch'', ''localtime'') as formatted_create_date, '
      + 'strftime(''%Y-%m-%d %H:%M:%S'', expires_utc/1000000, ''unixepoch'', ''localtime'') as formatted_expire_date, '
      + 'is_secure, is_httponly, has_expires, is_persistent FROM cookies';

    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    function GetBrowserPrefix: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Cookies: TCookieItems);
    procedure OutputJSON(const Cookies: TCookieItems);
    procedure OutputCSV(const Cookies: TCookieItems);
    procedure OutputCookies(const Cookies: TCookieItems);
    function DecryptValue(const EncryptedValue: TBytes): string;

  public
    constructor Create(const AProfilePath: string;
      ABrowserKind: TBrowserKind = bkChrome);
    destructor Destroy; override;
    function GetCookies: TCookieItems;
    procedure SortCookiesByDate(var Cookies: TCookieItems);
    function GetCookieCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TChromiumCookieHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

function TChromiumCookieHelper.GetBrowserPrefix: string;
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

function TChromiumCookieHelper.DecryptValue(const EncryptedValue
  : TBytes): string;
var
  DecryptedBytes: TBytes;
begin
  Result := '';
  if Length(EncryptedValue) > 0 then
  begin
    // Try DPAPI first
    DecryptedBytes := ChromiumCrypto.DecryptWithDPAPI(EncryptedValue);
    if Length(DecryptedBytes) > 0 then
      try
        Result := TEncoding.UTF8.GetString(DecryptedBytes);
      except
        Result := '';
      end
    else
    begin
      // Try AES-GCM
      var
      MasterKey := ChromiumCrypto.GetMasterKey(FProfilePath);
      if Length(MasterKey) > 0 then
      begin
        DecryptedBytes := ChromiumCrypto.DecryptWithChromium(MasterKey,
          EncryptedValue);
        if Length(DecryptedBytes) > 0 then
          try
            Result := TEncoding.UTF8.GetString(DecryptedBytes);
          except
            // Fallback to raw char conversion if UTF8 fails
            for var i := 0 to Length(DecryptedBytes) - 1 do
              if DecryptedBytes[i] >= 32 then
                Result := Result + Char(DecryptedBytes[i]);
          end;
      end;
    end;
  end;
end;

procedure TChromiumCookieHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TChromiumCookieHelper.OutputHuman(const Cookies: TCookieItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_cookies.txt', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in Cookies do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'Host: ', Item.Host);
      WriteLn(OutputFile, 'Path: ', Item.Path);
      WriteLn(OutputFile, 'Name: ', Item.KeyName);
      WriteLn(OutputFile, 'Value: ', Item.Value);
      WriteLn(OutputFile, 'Secure: ', Item.IsSecure);
      WriteLn(OutputFile, 'HTTPOnly: ', Item.IsHTTPOnly);
      WriteLn(OutputFile, 'Has Expire: ', Item.HasExpire);
      WriteLn(OutputFile, 'Persistent: ', Item.IsPersistent);
      WriteLn(OutputFile, 'Created: ', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.CreateDate));
      WriteLn(OutputFile, 'Expires: ', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.ExpireDate));
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn(Format('[%s] Cookies  saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));

  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumCookieHelper.OutputJSON(const Cookies: TCookieItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in Cookies do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('host', TJSONString.Create(Item.Host));
      JSONObject.AddPair('path', TJSONString.Create(Item.Path));
      JSONObject.AddPair('keyName', TJSONString.Create(Item.KeyName));
      JSONObject.AddPair('value', TJSONString.Create(Item.Value));
      JSONObject.AddPair('secure', TJSONBool.Create(Item.IsSecure));
      JSONObject.AddPair('httpOnly', TJSONBool.Create(Item.IsHTTPOnly));
      JSONObject.AddPair('hasExpire', TJSONBool.Create(Item.HasExpire));
      JSONObject.AddPair('persistent', TJSONBool.Create(Item.IsPersistent));
      JSONObject.AddPair('created', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.CreateDate));
      JSONObject.AddPair('expires', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.ExpireDate));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('%s_%s_cookies.json',
      [GetBrowserPrefix, GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'),
      FileName);

    JSONString := JSONArray.Format(2);
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn(Format('[%s] Cookies  saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));

  finally
    JSONArray.Free;
  end;
end;

procedure TChromiumCookieHelper.OutputCSV(const Cookies: TCookieItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_cookies.csv', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile,
      'Host,Path,KeyName,Value,IsSecure,IsHTTPOnly,HasExpire,IsPersistent,CreateDate,ExpireDate');

    for var Item in Cookies do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s","%s",%s,%s,%s,%s,"%s","%s"',
        [StringReplace(Item.Host, '"', '""', [rfReplaceAll]),
        StringReplace(Item.Path, '"', '""', [rfReplaceAll]),
        StringReplace(Item.KeyName, '"', '""', [rfReplaceAll]),
        StringReplace(Item.Value, '"', '""', [rfReplaceAll]),
        BoolToStr(Item.IsSecure, True), BoolToStr(Item.IsHTTPOnly, True),
        BoolToStr(Item.HasExpire, True), BoolToStr(Item.IsPersistent, True),
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.CreateDate),
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.ExpireDate)]));
    end;

    WriteLn(Format('[%s] Cookies  saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));

  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumCookieHelper.OutputCookies(const Cookies: TCookieItems);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(Cookies);
    ofJSON:
      OutputJSON(Cookies);
    ofCSV:
      OutputCSV(Cookies);
  end;
end;

constructor TChromiumCookieHelper.Create(const AProfilePath: string;
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

destructor TChromiumCookieHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TChromiumCookieHelper.GetCookies: TCookieItems;
var
  Query: TUniQuery;
  CookieDb, TempDb: string;
  FS: TFormatSettings;
begin
  SetLength(Result, 0);
  //CookieDb := TPath.Combine(FProfilePath, 'Cookies');
  CookieDb := TPath.Combine(TPath.Combine(FProfilePath, 'Network'), 'Cookies');

  if not FileExists(CookieDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('cookies_%s.sqlite',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(CookieDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := QUERY_CHROMIUM_COOKIE;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          KeyName := Query.FieldByName('name').AsString;
          Host := Query.FieldByName('host_key').AsString;
          Path := Query.FieldByName('path').AsString;
          IsSecure := Query.FieldByName('is_secure').AsInteger = 1;
          IsHTTPOnly := Query.FieldByName('is_httponly').AsInteger = 1;
          HasExpire := Query.FieldByName('has_expires').AsInteger = 1;
          IsPersistent := Query.FieldByName('is_persistent').AsInteger = 1;

          // Decrypt the cookie value
          var
          EncryptedValue := Query.FieldByName('encrypted_value').AsBytes;
          Value := DecryptValue(EncryptedValue);

          var
          CreateDateStr := Query.FieldByName('formatted_create_date').AsString;
          var
          ExpireDateStr := Query.FieldByName('formatted_expire_date').AsString;

          try
            FS := TFormatSettings.Create;
            FS.DateSeparator := '-';
            FS.TimeSeparator := ':';
            FS.ShortDateFormat := 'yyyy-mm-dd';
            FS.LongTimeFormat := 'hh:nn:ss';
            CreateDate := StrToDateTime(CreateDateStr, FS);
            ExpireDate := StrToDateTime(ExpireDateStr, FS);
          except
            on E: Exception do
            begin
              WriteLn('Error parsing dates - Create:', CreateDateStr,
                ' Expire:', ExpireDateStr, ' - ', E.Message);
              CreateDate := 0;
              ExpireDate := 0;
            end;
          end;
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
      begin
        SortCookiesByDate(Result);
        OutputCookies(Result);
      end;

    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

procedure TChromiumCookieHelper.SortCookiesByDate(var Cookies: TCookieItems);
var
  i, j: Integer;
  temp: TCookieItem;
begin
  for i := Low(Cookies) to High(Cookies) - 1 do
    for j := i + 1 to High(Cookies) do
      if Cookies[i].CreateDate < Cookies[j].CreateDate then
      begin
        temp := Cookies[i];
        Cookies[i] := Cookies[j];
        Cookies[j] := temp;
      end;
end;

function TChromiumCookieHelper.GetCookieCount: Integer;
var
  Query: TUniQuery;
  CookieDb, TempDb: string;
begin
  Result := 0;
  CookieDb := TPath.Combine(FProfilePath, 'Cookies');

  if not FileExists(CookieDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('cookies_%s.sqlite',
    [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(CookieDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    try
      FSQLiteConnection.Connect;
      Query := TUniQuery.Create(nil);
      try
        Query.Connection := FSQLiteConnection;
        Query.SQL.Text := 'SELECT COUNT(*) as count FROM cookies';
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
