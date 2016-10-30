program fzr;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  WinAPI.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,
  Zlib64 in 'Zlib64.pas';

function GetSHA1(Data: TBytes): string;
var
  Enc: TEncoding;
begin
  Enc := TEncoding.Default;
  Result := THashSHA1.GetHashString(Enc.GetString(Data));
end;

function BytesToString(Data: TBytes): string;
var
  Enc: TEncoding;
begin
  Enc := TEncoding.Default;
  Result := Enc.GetString(Data);
end;

const
  ChunkSize = 64 * 1024 * 1024;
  BuffSize = 8 * 1024 * 1024;
  ReadSize = 4096 * 1024;
  DoVerify = False;

var
  LZip: TZCompressionStream;
  LUnZip: TZDecompressionStream;
  myStream1, myStream2, myStream3, myStream4, myStream5: TStream;
  Buffer: TBytes;
  LastPos, Count, I, J, X: Int64;
  OffsetList, LevelsList: TStringList;
  B1, B2: Byte;
  Bytes1, Bytes2, Bytes3: TBytes;
  Hash: string;
  Loaded: Boolean;

begin
  try
    Loaded := False;
    myStream5 := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
    myStream3 := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
    repeat
      SetLength(Buffer, BuffSize);
      myStream2 := TMemoryStream.Create;
      repeat
        X := myStream5.Read(Buffer, Length(Buffer));
        myStream2.Write(Buffer, X);
      until (X = 0) or (myStream2.Size >= ChunkSize);
      if myStream2.Size = 0 then
        Halt(0);
      OffsetList := TStringList.Create;
      LevelsList := TStringList.Create;
      if Trunc(myStream2.Size / ChunkSize) * ChunkSize = myStream2.Size then
        Count := Trunc(myStream2.Size / ChunkSize)
      else
        Count := Trunc(myStream2.Size / ChunkSize) + 1;
      for J := 1 to Count do
      begin
        myStream2.Position := (J - 1) * ChunkSize;
        myStream1 := TMemoryStream.Create;
        if J = Count then
          myStream1.CopyFrom(myStream2, myStream2.Size - myStream2.Position)
        else
          myStream1.CopyFrom(myStream2, ChunkSize);
        myStream1.Position := 0;
        for I := 0 to myStream1.Size - 1 do
        begin
          B2 := B1;
          myStream1.Read(B1, 1);
          if ((B2 = $78) and ((B1 = $9C) or (B1 = $DA))) then
          begin
            OffsetList.Add(IntToStr(((J - 1) * ChunkSize) +
              (myStream1.Position - 2)));
            case B1 of
              $9C:
                LevelsList.Add('6');
              $DA:
                LevelsList.Add('9');
            end;
          end;
        end;
        myStream1.Free;
      end;
      myStream1 := TMemoryStream.Create;
      LastPos := 0;
      myStream2.Position := 0;
      SetLength(Bytes3, 10);
      Bytes3 := BytesOf('RZRREFLATE');
      myStream1.Write(Bytes3, Length(Bytes3));
      if OffsetList.Count > 0 then
      begin
        SetLength(Bytes3, 10);
        Bytes3 := BytesOf(IntToHex(StrToInt64(OffsetList[0]), 10));
        myStream1.Write(Bytes3, Length(Bytes3));
        if StrToInt64(OffsetList[0]) > 0 then
          myStream1.CopyFrom(myStream2, StrToInt64(OffsetList[0]));
      end
      else
      begin
        SetLength(Bytes3, 10);
        Bytes3 := BytesOf(IntToHex(myStream2.Size, 10));
        myStream1.Write(Bytes3, Length(Bytes3));
        if myStream2.Size > 0 then
          myStream1.CopyFrom(myStream2, myStream2.Size);
      end;
      for I := 0 to OffsetList.Count - 1 do
      begin
        myStream2.Position := StrToInt64(OffsetList[I]);
        if LastPos > myStream2.Position then
        begin
          myStream2.Position := LastPos;
          if (I + 1 = OffsetList.Count) then
          begin
            if myStream2.Size > LastPos then
            begin
              SetLength(Bytes3, 10);
              Bytes3 := BytesOf(IntToHex(myStream2.Size - LastPos, 10));
              myStream1.Write(Bytes3, Length(Bytes3));
              myStream1.CopyFrom(myStream2, myStream2.Size - LastPos);
            end;
          end
          else if StrToInt64(OffsetList[I + 1]) > LastPos then
          begin
            SetLength(Bytes3, 10);
            Bytes3 := BytesOf(IntToHex(StrToInt64(OffsetList[I + 1]) -
              LastPos, 10));
            myStream1.Write(Bytes3, Length(Bytes3));
            myStream1.CopyFrom(myStream2, StrToInt64(OffsetList[I + 1])
              - LastPos);
          end;
          continue;
        end;
        myStream2.Position := StrToInt64(OffsetList[I]);
        try
          LUnZip := TZDecompressionStream.Create(myStream2);
          SetLength(Bytes1, ReadSize);
          LUnZip.Read(Bytes1, Length(Bytes1));
          SetLength(Bytes1, LUnZip.OutputSize);
          if LUnZip.OutputSize = ReadSize then
            raise Exception.Create('Buffer error');
          if DoVerify then
          begin
            myStream2.Position := StrToInt64(OffsetList[I]);
            SetLength(Bytes2, LUnZip.InputSize);
            myStream2.Read(Bytes2, Length(Bytes2));
            Hash := GetSHA1(Bytes2);
            myStream4 := TBytesStream.Create;
            LZip := TZCompressionStream.Create(myStream4,
              StrToInt(LevelsList[I]), 8, 15);
            LZip.Write(Bytes1, Length(Bytes1));
            LZip.Free;
            SetLength(Bytes3, myStream4.Size);
            myStream4.Position := 0;
            myStream4.Read(Bytes3, Length(Bytes3));
            myStream4.Free;
            if Hash <> GetSHA1(Bytes3) then
              raise Exception.Create('Checksum does not match');
          end;
          SetLength(Bytes3, 10);
          Bytes3 := BytesOf(IntToHex(Length(Bytes1), 8) + 'L' + LevelsList[I]);
          myStream1.Write(Bytes3, Length(Bytes3));
          myStream1.Write(Bytes1, Length(Bytes1));
          LastPos := StrToInt64(OffsetList[I]) + LUnZip.InputSize;
          if (I + 1 = OffsetList.Count) then
          begin
            if myStream2.Size > LastPos then
            begin
              SetLength(Bytes3, 10);
              Bytes3 := BytesOf(IntToHex(myStream2.Size - LastPos, 10));
              myStream1.Write(Bytes3, Length(Bytes3));
              myStream1.CopyFrom(myStream2, myStream2.Size - LastPos);
            end;
          end
          else if StrToInt64(OffsetList[I + 1]) > LastPos then
          begin
            SetLength(Bytes3, 10);
            Bytes3 := BytesOf(IntToHex(StrToInt64(OffsetList[I + 1]) -
              LastPos, 10));
            myStream1.Write(Bytes3, Length(Bytes3));
            myStream1.CopyFrom(myStream2, StrToInt64(OffsetList[I + 1])
              - LastPos);
          end;
          LUnZip.Free;
        except
          on E: Exception do
          begin
            LUnZip.Free;
            myStream2.Position := StrToInt64(OffsetList[I]);
            if (I + 1 = OffsetList.Count) then
            begin
              if myStream2.Size > myStream2.Position then
              begin
                SetLength(Bytes3, 10);
                Bytes3 := BytesOf
                  (IntToHex(myStream2.Size - myStream2.Position, 10));
                myStream1.Write(Bytes3, Length(Bytes3));
                myStream1.CopyFrom(myStream2,
                  myStream2.Size - myStream2.Position);
              end;
            end
            else if StrToInt64(OffsetList[I + 1]) > StrToInt64(OffsetList[I])
            then
            begin
              SetLength(Bytes3, 10);
              Bytes3 := BytesOf(IntToHex(StrToInt64(OffsetList[I + 1]) -
                StrToInt64(OffsetList[I]), 10));
              myStream1.Write(Bytes3, Length(Bytes3));
              myStream1.CopyFrom(myStream2, StrToInt64(OffsetList[I + 1]) -
                StrToInt64(OffsetList[I]));
            end;
          end;
        end;
      end;
      myStream3.CopyFrom(myStream1, 0);
      OffsetList.Free;
      LevelsList.Free;
      myStream1.Free;
      myStream2.Free;
    until Loaded = True;
    SetLength(Bytes3, 10);
    Bytes3 := BytesOf('ENDZSTREAM');
    myStream3.Write(Bytes3, Length(Bytes3));
    { TODO -oUser -cConsole Main : Insert code here }
  except
    on E: Exception do
      WriteLn(E.ClassName, ': ', E.Message);
  end;

end.
