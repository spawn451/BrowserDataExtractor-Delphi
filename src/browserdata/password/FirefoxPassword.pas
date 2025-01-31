unit FirefoxPassword;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.NetEncoding,
  FirefoxCrypto;

type
  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TLoginData = record
    FormSubmitURL: string;  // Form submission URL
    Hostname: string;       // Website hostname
    Origin: string;        // Origin URL
    HttpRealm: string;     // HTTP auth realm
    Username: string;
    Password: string;
    CreateDate: Int64;
  end;

  TLoginDataArray = TArray<TLoginData>;

  TFirefoxPasswordHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FMasterKeyHelper: TMasterKeyHelper;
    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure ExtractURLs(const JSONItem: TJSONValue; var LoginData: TLoginData);
    procedure OutputHuman(const Credentials: TLoginDataArray);
    procedure OutputJSON(const Credentials: TLoginDataArray);
    procedure OutputCSV(const Credentials: TLoginDataArray);
    procedure OutputCredentials(const Credentials: TLoginDataArray);
    function LoadFirefoxLoginData: TLoginDataArray;
  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetPasswords: TLoginDataArray;
    function GetPasswordCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxPasswordHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

procedure TFirefoxPasswordHelper.ExtractURLs(const JSONItem: TJSONValue; var LoginData: TLoginData);
begin
  // Extract all URL-related fields
  LoginData.FormSubmitURL := JSONItem.GetValue<string>('formSubmitURL', '');
  LoginData.Hostname := JSONItem.GetValue<string>('hostname', '');
  LoginData.Origin := JSONItem.GetValue<string>('origin', '');
  LoginData.HttpRealm := JSONItem.GetValue<string>('httpRealm', '');
end;

constructor TFirefoxPasswordHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV; // Default to CSV
  FMasterKeyHelper := TMasterKeyHelper.Create(AProfilePath);
end;

destructor TFirefoxPasswordHelper.Destroy;
begin
  FMasterKeyHelper.Free;
  inherited;
end;

procedure TFirefoxPasswordHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxPasswordHelper.OutputHuman(const Credentials: TLoginDataArray);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_passwords.txt', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var i := 0 to Length(Credentials) - 1 do
    begin
      WriteLn(OutputFile);
      if Credentials[i].FormSubmitURL <> '' then
        WriteLn(OutputFile, 'Form Submit URL: ', Credentials[i].FormSubmitURL);
      if Credentials[i].Hostname <> '' then
        WriteLn(OutputFile, 'Hostname: ', Credentials[i].Hostname);
      if Credentials[i].Origin <> '' then
        WriteLn(OutputFile, 'Origin: ', Credentials[i].Origin);
      if Credentials[i].HttpRealm <> '' then
        WriteLn(OutputFile, 'HTTP Realm: ', Credentials[i].HttpRealm);
      WriteLn(OutputFile, 'Username: ', Credentials[i].Username);
      WriteLn(OutputFile, 'Password: ', Credentials[i].Password);
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn('[FIREFOX] Passwords saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxPasswordHelper.OutputJSON(const Credentials: TLoginDataArray);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var i := 0 to Length(Credentials) - 1 do
    begin
      JSONObject := TJSONObject.Create;

      if Credentials[i].FormSubmitURL <> '' then
        JSONObject.AddPair('formSubmitURL', TJSONString.Create(Credentials[i].FormSubmitURL));
      if Credentials[i].Hostname <> '' then
        JSONObject.AddPair('hostname', TJSONString.Create(Credentials[i].Hostname));
      if Credentials[i].Origin <> '' then
        JSONObject.AddPair('origin', TJSONString.Create(Credentials[i].Origin));
      if Credentials[i].HttpRealm <> '' then
        JSONObject.AddPair('httpRealm', TJSONString.Create(Credentials[i].HttpRealm));

      JSONObject.AddPair('username', TJSONString.Create(Credentials[i].Username));
      JSONObject.AddPair('password', TJSONString.Create(Credentials[i].Password));

      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_passwords.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] Passwords saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxPasswordHelper.OutputCSV(const Credentials: TLoginDataArray);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_passwords.csv', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'FormSubmitURL,Hostname,Origin,HttpRealm,Username,Password');

    for var Cred in Credentials do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s","%s","%s","%s"',
        [
          StringReplace(Cred.FormSubmitURL, '"', '""', [rfReplaceAll]),
          StringReplace(Cred.Hostname, '"', '""', [rfReplaceAll]),
          StringReplace(Cred.Origin, '"', '""', [rfReplaceAll]),
          StringReplace(Cred.HttpRealm, '"', '""', [rfReplaceAll]),
          StringReplace(Cred.Username, '"', '""', [rfReplaceAll]),
          StringReplace(Cred.Password, '"', '""', [rfReplaceAll])
        ]));
    end;

    WriteLn('[FIREFOX] Passwords saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxPasswordHelper.OutputCredentials(const Credentials: TLoginDataArray);
begin
  case FOutputFormat of
    ofHuman: OutputHuman(Credentials);
    ofJSON:  OutputJSON(Credentials);
    ofCSV:   OutputCSV(Credentials);
  end;
end;

function TFirefoxPasswordHelper.LoadFirefoxLoginData: TLoginDataArray;
var
  JSONFile: string;
  JSONString: string;
  JSONValue: TJSONValue;
  JSONArray: TJSONArray;
  EncryptedUsernames, EncryptedPasswords: TArray<TBytes>;
begin
  SetLength(Result, 0);
  JSONFile := TPath.Combine(FProfilePath, 'logins.json');

  if not FileExists(JSONFile) then
  begin
    //WriteLn('Debug: logins.json not found at ', JSONFile);
    Exit;
  end;

  try
    JSONString := TFile.ReadAllText(JSONFile);
    JSONValue := TJSONObject.ParseJSONValue(JSONString);
    if not Assigned(JSONValue) then
    begin
      WriteLn('Debug: Failed to parse JSON');
      Exit;
    end;

    try
      if not(JSONValue is TJSONObject) then
      begin
        WriteLn('Debug: Root JSON is not an object');
        Exit;
      end;

      JSONArray := TJSONObject(JSONValue).GetValue<TJSONArray>('logins');
      if not Assigned(JSONArray) then
      begin
        WriteLn('Debug: No logins array found');
        Exit;
      end;

      SetLength(Result, JSONArray.Count);
      SetLength(EncryptedUsernames, JSONArray.Count);
      SetLength(EncryptedPasswords, JSONArray.Count);

      for var i := 0 to JSONArray.Count - 1 do
      begin
        // Extract all URL fields
        ExtractURLs(JSONArray.Items[i], Result[i]);
        Result[i].CreateDate := JSONArray.Items[i].GetValue<Int64>('timeCreated') div 1000;

        try
          EncryptedUsernames[i] := TNetEncoding.Base64.DecodeStringToBytes(
            JSONArray.Items[i].GetValue<string>('encryptedUsername'));
          EncryptedPasswords[i] := TNetEncoding.Base64.DecodeStringToBytes(
            JSONArray.Items[i].GetValue<string>('encryptedPassword'));
        except
          on E: Exception do
          begin
            WriteLn(Format('Debug: Failed to decode credentials for entry %d: %s', [i, E.Message]));
            Continue;
          end;
        end;
      end;

      // Get master key and decrypt credentials
      var MasterKey: TBytes;
      try
        MasterKey := FMasterKeyHelper.GetMasterKey;
      except
        on E: Exception do
        begin
          WriteLn('Debug: Failed to get master key: ', E.Message);
          Exit;
        end;
      end;

      // Decrypt usernames and passwords
      for var i := 0 to Length(Result) - 1 do
      begin
        try
          if Length(EncryptedUsernames[i]) > 0 then
          begin
            var UsernamePBE := NewASN1PBE(EncryptedUsernames[i]);
            Result[i].Username := TEncoding.UTF8.GetString(
              UsernamePBE.Decrypt(MasterKey)
            );
          end;
        except
          on E: Exception do
            WriteLn(Format('Debug: Failed to decrypt username for entry %d: %s', [i, E.Message]));
        end;

        try
          if Length(EncryptedPasswords[i]) > 0 then
          begin
            var PasswordPBE := NewASN1PBE(EncryptedPasswords[i]);
            Result[i].Password := TEncoding.UTF8.GetString(
              PasswordPBE.Decrypt(MasterKey)
            );
          end;
        except
          on E: Exception do
            WriteLn(Format('Debug: Failed to decrypt password for entry %d: %s', [i, E.Message]));
        end;
      end;

    finally
      JSONValue.Free;
    end;
  except
    on E: Exception do
    begin
      WriteLn('Debug: Unexpected error: ', E.Message);
      SetLength(Result, 0);
    end;
  end;
end;

function TFirefoxPasswordHelper.GetPasswords: TLoginDataArray;
begin
  Result := LoadFirefoxLoginData;
  if Length(Result) > 0 then
    OutputCredentials(Result);
end;

function TFirefoxPasswordHelper.GetPasswordCount: Integer;
var
  JSONFile: string;
  JSONString: string;
  JSONValue: TJSONValue;
  JSONArray: TJSONArray;
begin
  Result := 0;
  JSONFile := TPath.Combine(FProfilePath, 'logins.json');

  if not FileExists(JSONFile) then
    Exit;

  try
    JSONString := TFile.ReadAllText(JSONFile);
    JSONValue := TJSONObject.ParseJSONValue(JSONString);
    if Assigned(JSONValue) then
    try
      if JSONValue is TJSONObject then
      begin
        JSONArray := TJSONObject(JSONValue).GetValue<TJSONArray>('logins');
        if Assigned(JSONArray) then
          Result := JSONArray.Count;
      end;
    finally
      JSONValue.Free;
    end;
  except
    Result := 0;
  end;
end;

end.
