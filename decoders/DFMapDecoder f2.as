/** 
* @mxmlc -default-size 600 400 -incremental=true -use-network=false
*/
package {
	
	import flash.events.*
	import flash.display.Colours;
	
	import flash.display.BitmapData;
	import flash.geom.Rectangle;
	
	import flash.utils.*;
	import flash.net.*;
	
	
	public class DFMapDecoder extends EventDispatcher
	{		
		private var md_mapStream:ByteArray;
		private var md_loader:URLLoader;
		
		public var negativeVersion:int;
		public var numberOfTiles:uint;
		public var tileWidth:uint;
		public var tileHeight:uint;
		public var mapWidthInTiles:uint;
		public var mapHeightInTiles:uint;
		public var numberOfMapLayers:uint;
		
		public var tileIndex:Array;
		public var mapLayers:Array;
		
		public function DecryptTest():void
		{

		}
		
		public function loadCompressedFile(str:String):void
		{
			var url:URLRequest;
			
			url = new URLRequest(str);			
			md_loader = new URLLoader();
			md_loader.dataFormat = URLLoaderDataFormat.BINARY;
			
			md_loader.addEventListener("complete", processLoadComplete);
			md_loader.addEventListener("ioError", handleError);
			md_loader.addEventListener("securityError", handleError);
			
			try
			{
				md_loader.load(url);
			}
			catch(e:SecurityError)
			{
				handleError(new ErrorEvent("securityError", false, false, e.message));
			}
		}
		
		private function processLoadComplete(evt:Object):void
		{
			dispatchEvent(new Event("onLoad"));
		}
		
		public function decodeFile():void
		{
			var k:uint, t:uint, i:uint, j:uint;
			var mapLayer:Object;
			
			/* DECODE PHASE - Uncompress data, set endian */
			md_mapStream = md_loader.data;
			
			if(md_mapStream == null)
			{
				dispatchEvent(new ErrorEvent("ioError", false, false, "No binary file loaded. Use loadCompressedFile() and listen for 'onLoad' before calling this method."));
				return;
			}
			
			md_mapStream.endian = Endian.LITTLE_ENDIAN;
		
			try
			{
				md_mapStream.uncompress();		
			}
			catch(error:Error)
			{
				dispatchEvent(new ErrorEvent("ioError", false, false, "Could not decompress map stream, continuing to use uncompressed format."));
			}
			
			/* Version 0 FDF-Maps:
				Int32 numberOfTiles (Number of unique tile images - not the total number of tiles in the map)
				Int32 tileWidth (width of each tile in pixels)
				Int32 tileHeight (height of each tile in pixels)
				
				Int32 mapWidthInTiles (number of columns of tiles in the map)
				Int32 mapHeightInTiles (number of rows of tiles in the map)
			*/
			
			/* Version -1 FDF-Maps:
				Int32 negativeVersion (this would be -1 for the new multi-layer-supporting format, or >=0 for the previous format, which doesn't support multi-layer images. For the doc on the previous format, see DFMapViewer_FileFormat.txt (this is DFMapViewer_FileFormat_2.txt. Note that this variable is numberOfTiles in the old format, and is guaranteed to be >=0 in it.))
				Int32 numberOfTiles (Number of unique tile images - not the total number of tiles in the map)
				Int32 tileWidth (width of each tile in pixels)
				Int32 tileHeight (height of each tile in pixels)

				Int32 numMapLayers (how many map layers are in the image - for an old DF image, this would be one)

				For each map layer:
					Int32 mapLayerDepth (This may change, but I'm thinking 0 would be the ground layer, and higher (towards the sky) layers (if any) would have positive numbers, and lower (deeper) layers would have negative numbers - higher numbers are higher altitude, lower numbers are lower altitude.)
					Int32 mapLayerWidthInTiles (number of columns of tiles in this map layer)
					Int32 mapLayerHeightInTiles (number of rows of tiles in this map layer)
			*/
			
			/* READ PHASE 1 - Map variables */
			trace("Decode Map Start");
			
			negativeVersion = md_mapStream.readInt();
			
			if(negativeVersion >= 0)
			{
				numberOfTiles = negativeVersion;
				trace(" Number of Tiles: "+numberOfTiles);
			}
			else
			{
				trace(" Negative Version: "+negativeVersion);
				numberOfTiles = md_mapStream.readUnsignedInt();
			}
			
			tileWidth = md_mapStream.readUnsignedInt();
			tileHeight = md_mapStream.readUnsignedInt();
			
			trace(" Tile Width: "+tileWidth);
			trace(" Tile Height: "+tileHeight);
			
			mapLayers = new Array();
			if(negativeVersion < 0)
			{
				numberOfMapLayers = md_mapStream.readUnsignedInt();
				trace(" Found "+numberOfMapLayers+" numberOfMapLayers");
				for(k=0; k<numberOfMapLayers; k++)
				{
					mapLayer = new Object();
					mapLayer["depth"] = md_mapStream.readInt();
					mapLayer["widthInTiles"] = md_mapStream.readUnsignedInt();
					mapLayer["heightInTiles"] = md_mapStream.readUnsignedInt();
					
					// Track largest values
					if(mapLayer["widthInTiles"] > mapWidthInTiles)
						mapWidthInTiles = mapLayer["widthInTiles"];
					if(mapLayer["heightInTiles"] > mapHeightInTiles)
						mapHeightInTiles = mapLayer["heightInTiles"];
						
					//mapLayer["tileData"] ... array
					mapLayers.push(mapLayer);	
					
					trace(" Decoded mapLayer, depth: "+mapLayer["depth"]);
				}
			}
			else
			{
				numberOfMapLayers = 1;
				trace(" Defaulted to single (1) numberOfMapLayers");
				mapLayer = new Object();
				mapLayer["depth"] = 0;
				mapLayer["widthInTiles"] = md_mapStream.readUnsignedInt();
				mapLayer["heightInTiles"] = md_mapStream.readUnsignedInt();
				
				mapWidthInTiles = mapLayer["widthInTiles"];
				mapHeightInTiles = mapLayer["heightInTiles"];
				
				//mapLayer["tileData"] ... array
				mapLayers.push(mapLayer);
			}
			
			trace("DecodeMap : Phase 1 Complete");
			
			/* READ PHASE 2 - Tile index */
			var tile:BitmapData;
			var tileRectangle:Rectangle;
			var blankTile:BitmapData;
			
			tileIndex = new Array();
			tileRectangle = new Rectangle(0, 0, tileWidth, tileHeight);
			
			blankTile = new BitmapData(tileWidth, tileHeight, false, Colours.C_BLACK);
			
			var tileByteLength:uint = tileWidth * tileHeight * 4;
			
			trace("DecodeMap : Phase 2A Complete");
			
			for(t=0; t<numberOfTiles; t++)
			{
				try
				{
					tile = new BitmapData(tileWidth, tileHeight, true, Colours.C_BLACK);
				}
				catch(error:Error)
				{
					dispatchEvent(new ErrorEvent("ioError", false, false, error.message +" Map Decoder Phase 2A, while parsing map file, internal Flash error. "));
					return;
				}
				
				try
				{	
					var tileBytesLoaded:uint = 0;
					var RLEBytes:ByteArray = new ByteArray();
					var tileBytes:ByteArray = new ByteArray();

					while (tileBytesLoaded < tileByteLength)
					{
						md_mapStream.readBytes(RLEBytes, 0, 4);
						var streamLength:uint = RLEBytes.bytesAvailable;
						if (streamLength == 4)
						{
							
							//traceMessage("n: " + RLEBytes[0] + " r: "+RLEBytes[1] + " g: " + RLEBytes[2] + " b: " + RLEBytes[3]);
							for (var numPixels:uint = RLEBytes[0]; numPixels>0; numPixels--)
							{
								tileBytes[tileBytesLoaded]   = 255;			 // Alpha
								tileBytes[tileBytesLoaded+1] = RLEBytes[3]; // Red
								tileBytes[tileBytesLoaded+2] = RLEBytes[2]; // Green
								tileBytes[tileBytesLoaded+3] = RLEBytes[1]; // Blue
								tileBytesLoaded = tileBytesLoaded + 4;
							}
						}
						else
						{
							dispatchEvent(new ErrorEvent("IOError", false, false, "File is incomplete? (Truncated in a tile image)"));
							return; // Kill process
						}
					}
				}
				catch(error:Error)
				{
					dispatchEvent(new ErrorEvent("IOError", false, false, error.message + " Happened during Tile Index Decoding"));	
					return;
				}
		
				tile.setPixels(tileRectangle, tileBytes);
				tileIndex.push(tile);
			}
			
			trace("DecodeMap : Phase 2B Complete");
			
			/* READ PHASE 3 - Map indexes */
			var VarSize:uint;
			
			if(numberOfTiles <= 255)
			{
				VarSize = 1;	// Use Uint8			
			}
			else
			if(numberOfTiles <= 65536)
			{
				VarSize = 2;	// Use Uint16 
			}
			else
			{
				VarSize = 3;	// Use Uint32
			}
			
			var index:uint;
			try
			{
				for(k=0; k<numberOfMapLayers; k++)
				{
					mapLayer = mapLayers[k];
					mapLayer["tileData"] = new Array(mapLayer["widthInTiles"]);
					
					for(i=0; i<mapLayer["widthInTiles"]; i++)
					{
						mapLayer["tileData"][i] = new Array(mapLayer["heightInTiles"]);
						
						for(j=0; j<mapLayer["heightInTiles"]; j++)
						{
							switch(VarSize)
							{
								case 1:
									index = md_mapStream.readUnsignedByte();
								break;
								case 2:
									index = md_mapStream.readUnsignedShort();
								break;
								case 3:
								default:
									index = md_mapStream.readUnsignedInt();
								break;
							}
							mapLayer["tileData"][i][j] = index;
						}
					}
				}
			}
			catch(error:Error)
			{
				var varType:String;
				
				switch(VarSize)
				{
					case 1:
						varType = "unsigned byte";
					break;
					case 2:
						varType = "unsigned short";
					break;
					case 3:
					default:
						varType = "unsigned int";
					break;
				}
				throw new Error(error.message + " Happened while reading " + varType + " map indexes");
				return;
			}
			
			trace("DecodeMap : Phase 3 Complete");
			
			mapLayers.sortOn("depth", Array.NUMERIC);
			trace(" Sorting mapLayers:");
			for each(var ml:Object in mapLayers)
			{
				trace("  Sorted map layer: "+ml["depth"]);
			}
			
			trace("DecodeMap : Phase 4 Complete");
			
			dispatchEvent(new Event("decodeComplete"));
		}
		
		private function handleError(evt:Event):void
		{
			dispatchEvent(evt);
		}
	}
}
