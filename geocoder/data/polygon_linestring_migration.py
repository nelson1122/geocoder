#!/usr/bin/python
#
#Migracion de geometrias Linea y Polygono OSM a PostgreSQL
#
#Este algoritmo permite la migracion de communas, barrios y vias digitalizadas
#con el editor JOSM al esquema de datos del geocodificador instalado en PostgreSQL
#
#
import sys, getopt, xml, re, psycopg2, string

from xml.dom.minidom import parse
from xml.parsers.expat import ExpatError

from osgeo import ogr
from osgeo import osr

#argumentos por linea de comandos predeterminados
osmfile	= '' 			#-f <file access path>
host 	= 'localhost' 	#-h <host address>
port 	= '5432' 		#-p <port>
dbname 	= '' 			#-d <database name>
usr 	= 'postgres' 	#-u <user_name>
pwd 	= '' 			#-w <password>
op 		= 'l'			#-o l (linestring) p (polygon)
table	= ''			#-t	c (communes) n (neighborhoods) r (roads)

try:
	myopts, args = getopt.getopt(sys.argv[1:], "f:h:p:d:u:w:o:t:")		
	for opt, arg in myopts:
		if opt == '-f':
			osmfile = arg
		elif opt == '-h':
			host = arg
		elif opt == '-p':
			port = arg
		elif opt == '-d':
			dbname = arg
		elif opt == '-u':
			usr = arg
		elif opt == '-w':
			pwd = arg
		elif opt == '-o':
			op = arg
		elif opt == '-t':
			table = arg

except getopt.GetoptError as e:
    print ('\nMigration Script Error: ' + str(e))
    sys.exit(0)
    
if osmfile != '' and dbname != '' and op in ('l', 'p'):
	try:
		#%%%%%%%%%%%%%%%%%%%%%%
		
		xmls = parse(osmfile)

		#Conexion a la base de datos con psycopg2 y creacion del cursor de consultas
		conn_string = "host='" + host + "' dbname='" + dbname + "' user='" + usr + "' password='" + pwd + "'"
		pg_conn = psycopg2.connect(conn_string)
		cursor = pg_conn.cursor()

		#Almacenamiento de los nodos para posterior recuperacion a partir de
		#los atributos de referencia "ref"
		nodes = {}
		for n in xmls.getElementsByTagName("node"):
			nodes[n.getAttribute("id")] = [n.getAttribute("lat"),n.getAttribute("lon")]
		del n

		for w in xmls.getElementsByTagName("way"):
			gid = w.getAttribute("id")
			gtags = {}
			gtags["name"] = ""
			polyline = []	
			
			#Recorrido y obtencion de las etiquetas de la geometria w
			for tag in w.getElementsByTagName("tag"):
				if tag.hasAttribute("k") and tag.hasAttribute('v'):
					gtags[tag.getAttribute("k")] = re.sub(re.compile('[%s]' % re.escape(string.punctuation)),'',tag.getAttribute('v').upper())
				del tag

			geometry = None;
			
			#validar (convertir) si es LINESTRING O POLYGON
			if op == 'l':
				#Recorrido, obtencion, ordenamiento de las coordenadas de la geometria w
				geometry = ogr.Geometry(ogr.wkbLineString)
				for nd in w.getElementsByTagName('nd'):
					if nd.hasAttribute('ref'):
						lat = float(nodes[nd.getAttribute("ref")][0])
						lon = float(nodes[nd.getAttribute("ref")][1])
						
						point = ogr.Geometry(ogr.wkbPoint)
						point.AddPoint(lon, lat)
						
						inSpatialRef = osr.SpatialReference()
						inSpatialRef.ImportFromEPSG(4326)

						outSpatialRef = osr.SpatialReference()
						outSpatialRef.ImportFromEPSG(3857)
						
						coordTransform = osr.CoordinateTransformation(inSpatialRef, outSpatialRef)
						point.Transform(coordTransform)
						
						geometry.AddPoint(point.GetX(), point.GetY())
				del nd	
				
			elif op == 'p':
				# Create ring
				ring = ogr.Geometry(ogr.wkbLinearRing)
				for nd in w.getElementsByTagName('nd'):
					if nd.hasAttribute('ref'):
						lat = float(nodes[nd.getAttribute("ref")][0])
						lon = float(nodes[nd.getAttribute("ref")][1])
						
						point = ogr.Geometry(ogr.wkbPoint)
						point.AddPoint(lon, lat)
						
						inSpatialRef = osr.SpatialReference()
						inSpatialRef.ImportFromEPSG(4326)

						outSpatialRef = osr.SpatialReference()
						outSpatialRef.ImportFromEPSG(3857)
						
						coordTransform = osr.CoordinateTransformation(inSpatialRef, outSpatialRef)
						point.Transform(coordTransform)
						
						ring.AddPoint(point.GetX(), point.GetY())
				del nd
				# Create polygon
				geometry = ogr.Geometry(ogr.wkbPolygon)
				geometry.AddGeometry(ring)
				
			
			if gtags["name"] != "":
				query = '';
				if table == 'c': #comunas
					query = "INSERT INTO geocoder.communes (commune_name, commune_geometry) VALUES (%s, %s);"
				elif table == 'n': #barrions
					query = "INSERT INTO geocoder.neighborhoods (neighborhood_name, neighborhood_geometry) VALUES (%s, %s);"
				elif table == 'r': #vias
					query = "";
				
				cursor.execute(query, (gtags["name"], geometry.ExportToWkt()))
				
		cursor.close()
		pg_conn.commit()
		pg_conn.close()
		print ("\nScript Message: Address data migration was successful.")
		
		#%%%%%%%%%%%%%%%%%%%%%%
		
	except ExpatError as e:
		print ("\nMigration Script Error:\n" + str(e))
		sys.exit(0)
	except IOError as e:
		print ("\nMigration Script Error:\nInvalid osm file")
		sys.exit(0)
	except psycopg2.Error as e:
		print("\nMigration Script Error:\n" + str(e))
		sys.exit(0)
	except psycopg2.Error as e:
		print ("\nMigration Script Error:\n" + str(e))
		sys.exit(0)
	
else:
	if osmfile == '':
		print ("Migration Script Error: osmfile (-f) parameter must be configured")
	if dbname == '':
		print ("Migration Script Error: dbname  (-d) parameter must be configured")
	if op != 'l' or op != 'p':
		print ("Migration Script Error: type of geometry (-o) is not valid.")
