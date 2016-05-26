#!/usr/bin/python
# -*- coding: utf-8 -*-
import sys, getopt, xml, re, psycopg2, json
import xml.etree.ElementTree as ET

from xml.dom.minidom import parse
from xml.parsers.expat import ExpatError

from osgeo import ogr
from osgeo import osr



#argumentos por linea de comandos predeterminados
osmfile	= '' 			#-f <file access path>
host 	= 'localhost' 	#-h <host address>
port 	= '5432' 		#-p <port>
dbname 	= '' 			#-d <database name>
usr 	= 'postgres' 	#-u <user name>
pwd 	= '' 			#-w <password>

try:
	myopts, args = getopt.getopt(sys.argv[1:],"f:h:p:d:u:w:")		
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

except getopt.GetoptError as e:
    print ('\nMigration Script Error: ' + str(e) + "\n")
    sys.exit(0)
  
if osmfile != '' and dbname != '':
	try:
		
		print "\nProcess has started..\n"
		
		#acceso al DOM del archivo osm (xml)
		xmls = xml.dom.minidom.parse(osmfile)
		
		#creacion de la conexion a la base de datos donde se instalara el geocoder
		conn_string = "host='" + host + "' dbname='" + dbname + "' user='" + usr + "' password='" + pwd + "'"
		pg_conn = psycopg2.connect(conn_string)
		cursor = pg_conn.cursor()
	
		for n in xmls.getElementsByTagName("node"):
			nid = n.getAttribute("id")
			address_type = ""
			node_tags = {}
			
			if len(n.getElementsByTagName("tag")) != 0:

				#recorrido y obtencion de las etiquetas de los Puntos, con type_address se define
				#si la direccion es asignada segun la malla vial o segun el caso barrio - manzana - predio
				for tag in n.getElementsByTagName("tag"):
					node_tags[tag.getAttribute("k")] = tag.getAttribute("v")
				
				if 'addr:street' in node_tags.keys() or 'addr:full' in node_tags.keys() or 'addr:housenumber' in node_tags.keys():
					if re.match(u"^[MZ]{2} [A-ZÑ0-9]{1,3}$", node_tags["addr:full"]) and node_tags["addr:housenumber"] != "":
						address_type = "nblockhouseid_type"
				
					elif re.match("^[CLKRDGTV]{2}", node_tags["addr:street"]) and re.match("^[CLKRDG]{2}", node_tags["addr:full"]) and node_tags["addr:housenumber"].isdigit():
						address_type = "roadnetwork_type"
					
					else:
						print ("Migration Script Error: Tags doesn't have the correct format. 'addr:street = " + node_tags["addr:street"] + "' 'addr:full = " + node_tags["addr:full"] + "' 'addr:housenumber = " + node_tags["addr:housenumber"] + "'\n")
						sys.exit(0)
					
					#reproyeccion de coordenadas geograficas
					lon = float(n.getAttribute("lon"))
					lat = float(n.getAttribute("lat"))
					
					point = ogr.Geometry(ogr.wkbPoint)
					point.AddPoint(lon, lat)
					
					inSpatialRef = osr.SpatialReference()
					inSpatialRef.ImportFromEPSG(4326)

					outSpatialRef = osr.SpatialReference()
					outSpatialRef.ImportFromEPSG(3857)
					
					coordTransform = osr.CoordinateTransformation(inSpatialRef, outSpatialRef)
					
					point.Transform(coordTransform)
				
					if address_type == "roadnetwork_type":
						sql = "INSERT INTO geocoder.road_network_addresses (main_road, generated_road, distance, lon, lat) VALUES (%s, %s, %s, %s, %s);"
						cursor.execute(sql, (node_tags["addr:street"], node_tags["addr:full"], int(node_tags["addr:housenumber"]), point.GetX(), point.GetY()))
						
					elif address_type == "nblockhouseid_type":
						sql = "INSERT INTO geocoder.neighborhood_block_houseid_addresses (block, houseid, lon, lat) VALUES (%s, %s, %s, %s);"
						cursor.execute(sql, (node_tags["addr:full"], node_tags["addr:housenumber"], point.GetX(), point.GetY()))
				else:
					print "Skipping Unknown Tags for insertion: " + json.dumps(node_tags)
					
		cursor.close()
		pg_conn.commit()
		pg_conn.close()
		print ("\nScript Message: Address data migration was successful.\n")
		
	except ExpatError as e:
		print ("\nMigration Script Error:\n" + str(e))
		sys.exit(0)
	except IOError as e:
		print ("\nMigration Script Error:\nInvalid osm file\n")
		sys.exit(0)
	except psycopg2.Error as e:
		print("\nMigration Script Error: PostgreSQL Database Problem.\n" + str(e) + "\n")
		sys.exit(0)
	except ET.ParseError as e:
		print ("\nMigration Script Error:\n" + str(e) + "\n")
		sys.exit(0)
	except KeyError as e:
		print ("\nMigration Script Error:\nKey " + str(e) + " was not found in data. Keys found: " + json.dumps(node_tags) + "\n")
		print type(node_tags["addr:full"])
		sys.exit(0)
else:
	if osmfile == '':
		print ("\nMigration Script Error:\nosmfile (-f) parameter must be configured\n")
	if dbname == '':
		print ("\nMigration Script Error:\ndbname  (-d) parameter must be configured\n")
