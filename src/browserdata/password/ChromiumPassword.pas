unit ChromiumPassword;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  System.JSON, System.NetEncoding, System.Math, System.Generics.Collections,
  Winapi.Windows, Uni, SQLiteUniProvider, ChromiumCrypto;

type
  TBrowserKind = (bkChrome, bkBrave, bkEdge);
  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TLoginData = record
    UserName: string;
    Password: string;
    LoginURL: string;
    CreateDate: TDateTime;
  end;

  TLoginDataArray = TArray<TLoginData>;

  TChromiumPasswordHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FBrowserKind: TBrowserKind;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_Chromium_LOGIN = 'SELECT ' + '  origin_url, ' + '  username_value, ' +
      '  password_value, ' + '  date_created, ' +
      '  strftime(''%Y-%m-%d %H:%M:%S'', (date_created/1000000)-11644473600, ''unixepoch'', ''localtime'') as formatted_date '
      + 'FROM logins';

    function GetProfileName: string;
    function GetBrowserPrefix: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Logins: TLoginDataArray);
    procedure OutputJSON(const Logins: TLoginDataArray);
    procedure OutputCSV(const Logins: TLoginDataArray);
    procedure OutputLogins(const Logins: TLoginDataArray);
  public
    constructor Create(const AProfilePath: string;
      ABrowserKind: TBrowserKind = bkChrome);
    destructor Destroy; override;
    function GetPasswords: TLoginDataArray;
    function GetPasswordCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TChromiumPasswordHelper.GetProfileName: string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
end;

function TChromiumPasswordHelper.GetBrowserPrefix: string;
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

procedure TChromiumPasswordHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TChromiumPasswordHelper.OutputHuman(const Logins: TLoginDataArray);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_passwords.txt', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Login in Logins do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'URL: ', Login.LoginURL);
      WriteLn(OutputFile, 'Username: ', Login.UserName);
      WriteLn(OutputFile, 'Password: ', Login.Password);
      WriteLn(OutputFile, 'Created: ', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Login.CreateDate));
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn(Format('[%s] Passwords saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumPasswordHelper.OutputJSON(const Logins: TLoginDataArray);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Login in Logins do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('url', TJSONString.Create(Login.LoginURL));
      JSONObject.AddPair('username', TJSONString.Create(Login.UserName));
      JSONObject.AddPair('password', TJSONString.Create(Login.Password));
      JSONObject.AddPair('created', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Login.CreateDate));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('%s_%s_passwords.json',
      [GetBrowserPrefix, GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'),
      FileName);

    JSONString := JSONArray.Format(2);
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn(Format('[%s] Passwords saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    JSONArray.Free;
  end;
end;

procedure TChromiumPasswordHelper.OutputCSV(const Logins: TLoginDataArray);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_passwords.csv', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'URL,Username,Password,Created');

    for var Login in Logins do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s","%s"',
        [StringReplace(Login.LoginURL, '"', '""', [rfReplaceAll]),
        StringReplace(Login.UserName, '"', '""', [rfReplaceAll]),
        StringReplace(Login.Password, '"', '""', [rfReplaceAll]),
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Login.CreateDate)]));
    end;

    WriteLn(Format('[%s] Passwords saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumPasswordHelper.OutputLogins(const Logins: TLoginDataArray);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(Logins);
    ofJSON:
      OutputJSON(Logins);
    ofCSV:
      OutputCSV(Logins);
  end;
end;

constructor TChromiumPasswordHelper.Create(const AProfilePath: string;
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

destructor TChromiumPasswordHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;


function TChromiumPasswordHelper.GetPasswords: TLoginDataArray;
var
  Query: TUniQuery;
  LoginDb, TempDb: string;
  DateStr: string;
  FS: TFormatSettings;
  i: Integer;
begin
  SetLength(Result, 0);
  LoginDb := TPath.Combine(FProfilePath, 'Login Data');

  if not FileExists(LoginDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('login_%s.db', [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(LoginDb, TempDb, True);
    FSQLiteConnection.Database := TempDb;
    FSQLiteConnection.Connect;

    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := QUERY_Chromium_LOGIN;
      Query.Open;

      while not Query.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        with Result[High(Result)] do
        begin
          LoginURL := Query.FieldByName('origin_url').AsString;
          UserName := Query.FieldByName('username_value').AsString;

          var EncryptedPwd := Query.FieldByName('password_value').AsBytes;
          if Length(EncryptedPwd) > 0 then
          begin
            var MasterKey := ChromiumCrypto.GetMasterKey(FProfilePath);
            if Length(MasterKey) > 0 then
            begin
              var DecryptedBytes := ChromiumCrypto.DecryptWithChromium(MasterKey, EncryptedPwd);
              if Length(DecryptedBytes) > 0 then
              try
                Password := TEncoding.UTF8.GetString(DecryptedBytes);
              except
                Password := '';
                for i := 0 to Length(DecryptedBytes) - 1 do
                  if DecryptedBytes[i] >= 32 then
                    Password := Password + Char(DecryptedBytes[i]);
              end;
            end;
          end;

          // Date conversion
          DateStr := Query.FieldByName('formatted_date').AsString;
          try
            FS := TFormatSettings.Create;
            FS.DateSeparator := '-';
            FS.TimeSeparator := ':';
            FS.ShortDateFormat := 'yyyy-mm-dd';
            FS.LongTimeFormat := 'hh:nn:ss';
            CreateDate := StrToDateTime(DateStr, FS);
          except
            CreateDate := 0;
          end;
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
        OutputLogins(Result);

    finally
      Query.Free;
      FSQLiteConnection.Disconnect;
    end;

  finally
    if FileExists(TempDb) then
      TFile.Delete(TempDb);
  end;
end;

function TChromiumPasswordHelper.GetPasswordCount: Integer;
var
  Query: TUniQuery;
  LoginDb, TempDb: string;
begin
  Result := 0;
  LoginDb := TPath.Combine(FProfilePath, 'Login Data');

  if not FileExists(LoginDb) then
    Exit;

  TempDb := TPath.Combine(TPath.GetTempPath,
    Format('login_%s.db', [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(LoginDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    try
      FSQLiteConnection.Connect;
      Query := TUniQuery.Create(nil);
      try
        Query.Connection := FSQLiteConnection;
        Query.SQL.Text := 'SELECT COUNT(*) as count FROM logins';
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
