unit FirefoxCookie;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults, System.DateUtils, System.JSON, System.StrUtils,
  Uni, SQLiteUniProvider;

type
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

  TFirefoxCookieHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FSQLiteConnection: TUniConnection;

const
  QUERY_FIREFOX_COOKIE =
    'SELECT name, value, host, path, ' +
    'strftime(''%Y-%m-%d %H:%M:%S'', creationTime/1000000, ''unixepoch'', ''localtime'') as formatted_create_date, ' +
    'strftime(''%Y-%m-%d %H:%M:%S'', expiry, ''unixepoch'', ''localtime'') as formatted_expire_date, ' +
    'isSecure, isHttpOnly FROM moz_cookies';

    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';
    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Cookies: TCookieItems);
    procedure OutputJSON(const Cookies: TCookieItems);
    procedure OutputCSV(const Cookies: TCookieItems);
    procedure OutputCookies(const Cookies: TCookieItems);
  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetCookies: TCookieItems;
    procedure SortCookiesByDate(var Cookies: TCookieItems);
    function GetCookieCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxCookieHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

procedure TFirefoxCookieHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxCookieHelper.OutputHuman(const Cookies: TCookieItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_cookies.txt', [GetProfileName]);
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
    WriteLn('[FIREFOX] Cookies saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxCookieHelper.OutputJSON(const Cookies: TCookieItems);
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
      JSONObject.AddPair('created', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.CreateDate));
      JSONObject.AddPair('expires', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.ExpireDate));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_cookies.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] Cookies saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxCookieHelper.OutputCSV(const Cookies: TCookieItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_cookies.csv', [GetProfileName]);
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

    WriteLn('[FIREFOX] Cookies saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxCookieHelper.OutputCookies(const Cookies: TCookieItems);
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

constructor TFirefoxCookieHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV;
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TFirefoxCookieHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TFirefoxCookieHelper.GetCookies: TCookieItems;
var
  Query: TUniQuery;
  CookieDb, TempDb: string;
  FS: TFormatSettings;
begin
  SetLength(Result, 0);
  CookieDb := TPath.Combine(FProfilePath, 'cookies.sqlite');

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
      Query.SQL.Text := QUERY_FIREFOX_COOKIE;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          Host := Query.FieldByName('host').AsString;
          Path := Query.FieldByName('path').AsString;
          KeyName := Query.FieldByName('name').AsString;
          Value := Query.FieldByName('value').AsString;
          IsSecure := Query.FieldByName('isSecure').AsInteger = 1;
          IsHTTPOnly := Query.FieldByName('isHttpOnly').AsInteger = 1;
          HasExpire := True;
          IsPersistent := True;

          var CreateDateStr := Query.FieldByName('formatted_create_date').AsString;

          try
            FS := TFormatSettings.Create;
            FS.DateSeparator := '-';
            FS.TimeSeparator := ':';
            FS.ShortDateFormat := 'yyyy-mm-dd';
            FS.LongTimeFormat := 'hh:nn:ss';
            CreateDate := StrToDateTime(CreateDateStr, FS);
          except
            on E: Exception do
            begin
              WriteLn('Error parsing create date: ' + CreateDateStr + ' - ' + E.Message);
              CreateDate := 0;
            end;
          end;

          var ExpireDateStr := Query.FieldByName('formatted_expire_date').AsString;

          try
            ExpireDate := StrToDateTime(ExpireDateStr, FS);
          except
            on E: Exception do
            begin
              WriteLn('Error parsing expire date: ' + ExpireDateStr + ' - ' + E.Message);
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

procedure TFirefoxCookieHelper.SortCookiesByDate(var Cookies: TCookieItems);
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

function TFirefoxCookieHelper.GetCookieCount: Integer;
var
  Query: TUniQuery;
  CookieDb, TempDb: string;
begin
  Result := 0;
  CookieDb := TPath.Combine(FProfilePath, 'cookies.sqlite');

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
        Query.SQL.Text := 'SELECT COUNT(*) as count FROM moz_cookies';
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
