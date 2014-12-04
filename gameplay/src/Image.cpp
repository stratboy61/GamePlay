#include "Base.h"
#include "FileSystem.h"
#include "Image.h"

namespace gameplay
{
// Callback for reading a png image using Stream
static void readStream(png_structp png, png_bytep data, png_size_t length)
{
    Stream* stream = reinterpret_cast<Stream*>(png_get_io_ptr(png));
    if (stream == NULL || stream->read(data, 1, length) != length)
    {
        png_error(png, "Error reading PNG.");
    }
}

Image* Image::create(const char* path)
{
    GP_ASSERT(path);
    // Malek -- begin
    char newPath[512];
    strncpy(newPath, FileSystem::resolvePath(path), 512);
    char* ext = strrchr(newPath, '.');
    if (ext == NULL)
    {
        strncat(newPath, ".png", 5);
        if (!FileSystem::fileExists(newPath))
            return NULL;
    }
    // Malek -- end
    
    // Open the file.
    std::auto_ptr<Stream> stream(FileSystem::open(newPath));
    if (stream.get() == NULL || !stream->canRead())
    {
        GP_ERROR("Failed to open image file '%s'.", newPath);
        return NULL;
    }

    // Verify PNG signature.
    unsigned char sig[8];
    if (stream->read(sig, 1, 8) != 8 || png_sig_cmp(sig, 0, 8) != 0)
    {
        GP_ERROR("Failed to load file '%s'; not a valid PNG.", newPath);
        return NULL;
    }

    // Initialize png read struct (last three parameters use stderr+longjump if NULL).
    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (png == NULL)
    {
        GP_ERROR("Failed to create PNG structure for reading PNG file '%s'.", newPath);
        return NULL;
    }

    // Initialize info struct.
    png_infop info = png_create_info_struct(png);
    if (info == NULL)
    {
        GP_ERROR("Failed to create PNG info structure for PNG file '%s'.", newPath);
        png_destroy_read_struct(&png, NULL, NULL);
        return NULL;
    }

    // Set up error handling (required without using custom error handlers above).
    if (setjmp(png_jmpbuf(png)))
    {
        GP_ERROR("Failed to set up error handling for reading PNG file '%s'.", newPath);
        png_destroy_read_struct(&png, &info, NULL);
        return NULL;
    }

    // Initialize file io.
    png_set_read_fn(png, stream.get(), readStream);

    // Indicate that we already read the first 8 bytes (signature).
    png_set_sig_bytes(png, 8);

	// Get info from PNG header
	png_read_info(png, info);
	unsigned int width;
	unsigned int height;
	int bit_depth;
	int color_type;
	png_get_IHDR(png, info, &width, &height, &bit_depth, &color_type, NULL, NULL, NULL);

    Image* image = new Image();
    image->_width = width;
    image->_height = height;

    png_byte colorType = png_get_color_type(png, info);
    switch (colorType)
    {
    case PNG_COLOR_TYPE_RGBA:
        image->_format = Image::RGBA;
        break;

    case PNG_COLOR_TYPE_RGB:
        image->_format = Image::RGB;
	    break;

	case PNG_COLOR_TYPE_PALETTE:
	case PNG_COLOR_TYPE_GRAY:
		image->_format = Image::GREYSCALE;
		break;

    default:
        GP_ERROR("Unsupported PNG color type (%d) for image file '%s'.", (int)colorType, newPath);
        png_destroy_read_struct(&png, &info, NULL);
        return NULL;
    }

    if (bit_depth == 16) {
        png_set_strip_16(png);
	}

    if(color_type == PNG_COLOR_TYPE_RGBA && color_type == PNG_COLOR_TYPE_RGBA) {
		if (png_get_valid(png, info, PNG_INFO_tRNS)) {
			GP_ASSERT(colorType == PNG_COLOR_TYPE_RGBA);
			png_set_tRNS_to_alpha(png);    
		}
		//else // Malek: OpenGL does this automatically, no need to expand 24-bit RGB to RGBA
		//    png_set_filler(png, 0xff, PNG_FILLER_AFTER);
	}

    png_read_update_info(png, info);
	
    size_t stride = png_get_rowbytes(png, info);

    // Allocate image data.
    image->_data = new unsigned char[stride * image->_height];

    // Read rows into image data.
	png_bytepp row_pointers = (png_bytep *)new unsigned char[(sizeof(png_bytep) * height)];
    for (unsigned int i = 0; i < image->_height; ++i)
    {
		row_pointers[i] = (png_bytep)(image->_data + ((height - (i + 1)) * stride));
    }

	png_read_image(png, row_pointers);
	delete[] row_pointers;

    // Clean up.
    png_destroy_read_struct(&png, &info, NULL);

    return image;
}

Image::Image()
{
    // Unused
}

Image::~Image()
{
    SAFE_DELETE_ARRAY(_data);
}

}
