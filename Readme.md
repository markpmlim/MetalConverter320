Metal version of GraphicConverterIIGS.

The aim of this project (in the form of a Swift playground) is to investigate if it's possible to use a metal kernel function to convert a IIGS graphic to an instance of MTLTexture which will be rendered by a pair of vertex-fragment functions.


Requirements:

XCode 8.x, Swift 3.x or later

Hardware: A graphics processor which supports the Metal API

Knowhow: how to run a Swift playground

Because of changes in the interfaces, it is necessary to edit the file "Converter.swift" to run the playground demo in XCode 9.x or later.

To understand the source code, the programmer should have

a) a sound knowledge of the Fundamentals of the Metal API,

b) know the structure of an Apple IIGS graphic file with the format $C1/$0000, and,

c) basic knowledge of the Apple IIGS video hardware.



Acknowledgements:

Author: Marius Horga

For posting all those articles on "Using MetalKit" at http://metalkit.org

Author: Warren Moore

For posting all articles on www.metalbyexample.com


Author: Andy McFadden

For making his CiderPress source code available on the Internet.


Apple Computer

For making many Metal tutorials as well as articles available for downloading.
