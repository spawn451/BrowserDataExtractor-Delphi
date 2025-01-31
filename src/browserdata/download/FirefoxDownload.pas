unit FirefoxDownload;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults, System.DateUtils, System.JSON, System.StrUtils,
  Uni, SQLiteUniProvider;

type
  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TDownloadItem = record
    TargetPath: string;
    URL: string;
    TotalBytes: Int64;
    StartTime: TDateTime;
    EndTime: TDateTime;
    MimeType: string;
  end;

  TDownloadItems = TArray<TDownloadItem>;

  TFirefoxDownloadHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FSQLiteConnection: TUniConnection;
const
  QUERY_FIREFOX_DOWNLOAD =
    'SELECT place_id, GROUP_CONCAT(content) as content, url, ' +
    'strftime(''%Y-%m-%d %H:%M:%S'', dateAdded/1000000, ''unixepoch'', ''localtime'') as formatted_start_date, ' +
    'dateAdded ' +
    'FROM (SELECT * FROM moz_annos INNER JOIN moz_places ON ' +
    'moz_annos.place_id=moz_places.id) t GROUP BY place_id';

  CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Downloads: TDownloadItems);
    procedure OutputJSON(const Downloads: TDownloadItems);
    procedure OutputCSV(const Downloads: TDownloadItems);
    procedure OutputDownloads(const Downloads: TDownloadItems);
    function ParseJSONContent(const Content: string): TJSONObject;
  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetDownloads: TDownloadItems;
    procedure SortDownloadsBySize(var Downloads: TDownloadItems);
    function GetDownloadCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxDownloadHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

function TFirefoxDownloadHelper.ParseJSONContent(const Content: string): TJSONObject;
var
  ContentList: TArray<string>;
  JsonStr: string;
begin
  Result := nil;
  ContentList := Content.Split([',{']);
  if Length(ContentList) > 1 then
  begin
    JsonStr := '{' + ContentList[1];
    try
      Result := TJSONObject(TJSONObject.ParseJSONValue(JsonStr));
    except
      on E: Exception do
        WriteLn('Error parsing JSON: ', E.Message);
    end;
  end;
end;

procedure TFirefoxDownloadHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxDownloadHelper.OutputHuman(const Downloads: TDownloadItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_downloads.txt', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in Downloads do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'Target Path: ', Item.TargetPath);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Total Bytes: ', Item.TotalBytes);
      WriteLn(OutputFile, 'Start Time: ', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.StartTime));
      WriteLn(OutputFile, 'End Time: ', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.EndTime));
      if Item.MimeType <> '' then
        WriteLn(OutputFile, 'MIME Type: ', Item.MimeType);
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn('[FIREFOX] Downloads saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxDownloadHelper.OutputJSON(const Downloads: TDownloadItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in Downloads do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('targetPath', TJSONString.Create(Item.TargetPath));
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('totalBytes', TJSONNumber.Create(Item.TotalBytes));
      JSONObject.AddPair('startTime', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.StartTime));
      JSONObject.AddPair('endTime', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.EndTime));
      if Item.MimeType <> '' then
        JSONObject.AddPair('mimeType', TJSONString.Create(Item.MimeType));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_downloads.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] Downloads saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxDownloadHelper.OutputCSV(const Downloads: TDownloadItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_downloads.csv', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'TargetPath,URL,TotalBytes,StartTime,EndTime,MimeType');

    for var Item in Downloads do
    begin
      WriteLn(OutputFile, Format('"%s","%s",%d,"%s","%s","%s"',
        [
          StringReplace(Item.TargetPath, '"', '""', [rfReplaceAll]),
          StringReplace(Item.URL, '"', '""', [rfReplaceAll]),
          Item.TotalBytes,
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.StartTime),
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.EndTime),
          StringReplace(Item.MimeType, '"', '""', [rfReplaceAll])
        ]));
    end;

    WriteLn('[FIREFOX] Downloads saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxDownloadHelper.OutputDownloads(const Downloads: TDownloadItems);
begin
  case FOutputFormat of
    ofHuman: OutputHuman(Downloads);
    ofJSON:  OutputJSON(Downloads);
    ofCSV:   OutputCSV(Downloads);
  end;
end;

constructor TFirefoxDownloadHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV; // Default to CSV
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TFirefoxDownloadHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TFirefoxDownloadHelper.GetDownloads: TDownloadItems;
var
  Query: TUniQuery;
  DownloadDb, TempDb: string;
  JSONObj: TJSONObject;
  FS: TFormatSettings;
begin
  SetLength(Result, 0);
  DownloadDb := TPath.Combine(FProfilePath, 'places.sqlite');

  if not FileExists(DownloadDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('downloads_%s.sqlite', [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(DownloadDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := CLOSE_JOURNAL_MODE;
      Query.ExecSQL;
      Query.SQL.Text := QUERY_FIREFOX_DOWNLOAD;
      Query.Open;

      while not Query.Eof do
      begin
        var Content := Query.FieldByName('content').AsString;
        var ContentList := Content.Split([',{']);

        if Length(ContentList) > 1 then
        begin
          SetLength(Result, Length(Result) + 1);
          JSONObj := ParseJSONContent(Content);

          try
            with Result[High(Result)] do
            begin
              TargetPath := ContentList[0];
              URL := Query.FieldByName('url').AsString;

              // Handle start date
              var StartDateStr := Query.FieldByName('formatted_start_date').AsString;

              try
                FS := TFormatSettings.Create;
                FS.DateSeparator := '-';
                FS.TimeSeparator := ':';
                FS.ShortDateFormat := 'yyyy-mm-dd';
                FS.LongTimeFormat := 'hh:nn:ss';
                StartTime := StrToDateTime(StartDateStr, FS);
              except
                on E: Exception do
                begin
                  WriteLn('Error parsing start date: ' + StartDateStr + ' - ' + E.Message);
                  StartTime := 0;
                end;
              end;

              if Assigned(JSONObj) then
              begin
                TotalBytes := JSONObj.GetValue<Int64>('fileSize');

                // Handle end time from JSON
                var EndTimeStamp := JSONObj.GetValue<Int64>('endTime');
                if EndTimeStamp > 0 then
                begin
                  var EndDateStr := FormatDateTime('yyyy-mm-dd hh:nn:ss',
                    UnixToDateTime(EndTimeStamp div 1000));
                  try
                    EndTime := StrToDateTime(EndDateStr, FS);
                  except
                    on E: Exception do
                    begin
                      WriteLn('Error parsing end date: ' + EndDateStr + ' - ' + E.Message);
                      EndTime := 0;
                    end;
                  end;
                end
                else
                  EndTime := 0;
              end;
            end;
          finally
            JSONObj.Free;
          end;
        end;
        Query.Next;
      end;

      if Length(Result) > 0 then
      begin
        SortDownloadsBySize(Result);
        OutputDownloads(Result);
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

procedure TFirefoxDownloadHelper.SortDownloadsBySize(var Downloads: TDownloadItems);
var
  i, j: Integer;
  temp: TDownloadItem;
begin
  for i := Low(Downloads) to High(Downloads) - 1 do
    for j := i + 1 to High(Downloads) do
      if Downloads[i].TotalBytes < Downloads[j].TotalBytes then // Sort by size (largest first)
      begin
        temp := Downloads[i];
        Downloads[i] := Downloads[j];
        Downloads[j] := temp;
      end;
end;

function TFirefoxDownloadHelper.GetDownloadCount: Integer;
var
  Query: TUniQuery;
  DownloadDb, TempDb: string;
begin
  Result := 0;
  DownloadDb := TPath.Combine(FProfilePath, 'places.sqlite');

  if not FileExists(DownloadDb) then
    Exit;

  // Create temp copy of database
  TempDb := TPath.Combine(TPath.GetTempPath, Format('downloads_%s.sqlite', [TGUID.NewGuid.ToString]));
  try
    TFile.Copy(DownloadDb, TempDb);
    FSQLiteConnection.Database := TempDb;

    try
      FSQLiteConnection.Connect;
      Query := TUniQuery.Create(nil);
      try
        Query.Connection := FSQLiteConnection;
        Query.SQL.Text := QUERY_FIREFOX_DOWNLOAD;
        Query.Open;
        while not Query.Eof do
        begin
          var Content := Query.FieldByName('content').AsString;
          if Content.Contains(',{') then
            Inc(Result);
          Query.Next;
        end;
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
