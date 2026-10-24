unit UDialogIcons;

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Buttons, Vcl.VirtualImageList,
  AdvTypes;

procedure ConfigureDialogButtonImages(const aCollection: TAdvSVGImageCollection;
  const aImages: TVirtualImageList; const aCopyButton, aCloseButton: TBitBtn);

implementation

const
  cDialogCloseIconName = 'close';
  cDialogCopyIconName = 'copy';
  cSvgClose = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ' +
    'fill="none" stroke="#4B5563" stroke-width="1.9" stroke-linecap="round" ' +
    'stroke-linejoin="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';
  cSvgCopy = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ' +
    'fill="none" stroke="#4B5563" stroke-width="1.9" stroke-linecap="round" ' +
    'stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2"/>' +
    '<path d="M15 9V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h3"/></svg>';

procedure AddSvg(const aCollection: TAdvSVGImageCollection; const aName,
  aSvg: string);
var
  lBitmap: TAdvSVGBitmap;
  lItem: TAdvSVGImageCollectionItem;
  lStream: TStringStream;
begin
  lItem := aCollection.Images.Add;
  lItem.Name := aName;
  {$WARN CONSTRUCTING_ABSTRACT OFF}
  lBitmap := TAdvSVGBitmap.Create;
  {$WARN CONSTRUCTING_ABSTRACT ON}
  try
    lStream := TStringStream.Create(aSvg, TEncoding.UTF8);
    try
      lBitmap.LoadFromStream(lStream);
    finally
      lStream.Free;
    end;
    lItem.Data.Graphic := lBitmap;
  finally
    lBitmap.Free;
  end;
end;

procedure ConfigureDialogButtonImages(const aCollection: TAdvSVGImageCollection;
  const aImages: TVirtualImageList; const aCopyButton, aCloseButton: TBitBtn);
begin
  aImages.ImageCollection := nil;
  aCollection.Images.Clear;
  AddSvg(aCollection, cDialogCopyIconName, cSvgCopy);
  AddSvg(aCollection, cDialogCloseIconName, cSvgClose);
  aImages.AutoFill := True;
  aImages.ImageCollection := aCollection;
  if aCopyButton <> nil then
  begin
    aCopyButton.Images := aImages;
    aCopyButton.ImageIndex := aImages.GetIndexByName(cDialogCopyIconName);
  end;
  if aCloseButton <> nil then
  begin
    aCloseButton.Images := aImages;
    aCloseButton.ImageIndex := aImages.GetIndexByName(cDialogCloseIconName);
  end;
end;

end.
