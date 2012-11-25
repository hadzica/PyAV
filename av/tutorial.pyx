import os

import Image

cimport libav as lib


class LibError(ValueError):
    pass


cdef int errcheck(int res) except -1:
    cdef bytes py_buffer
    cdef char *c_buffer
    if res < 0:
        py_buffer = b"\0" * lib.AV_ERROR_MAX_STRING_SIZE
        c_buffer = py_buffer
        lib.av_strerror(res, c_buffer, lib.AV_ERROR_MAX_STRING_SIZE)
        raise LibError('%s (%d)' % (str(c_buffer), res))
    return res


def main(argv):
    
    print 'Starting.'
    
    cdef lib.AVFormatContext *format_ctx = NULL
    cdef int video_stream_i = 0
    cdef int i = 0
    cdef lib.AVCodecContext *codec_ctx = NULL
    cdef lib.AVCodec *codec = NULL
    cdef lib.AVDictionary *options = NULL
    
    if len(argv) < 2:
        print 'usage: tutorial <movie>'
        exit(1)
    filename = os.path.abspath(argv[1])
    
    print 'Registering codecs.'
    lib.av_register_all()
        
    print 'Opening', repr(filename)
    errcheck(lib.avformat_open_input(&format_ctx, filename, NULL, NULL))
    
    print 'Getting stream info.'
    errcheck(lib.avformat_find_stream_info(format_ctx, NULL))
    
    print 'Dumping to stderr.'
    lib.av_dump_format(format_ctx, 0, filename, 0);
    
    print format_ctx.nb_streams, 'streams.'
    print 'Finding first video stream...'
    for i in range(format_ctx.nb_streams):
        if format_ctx.streams[i].codec.codec_type == lib.AVMEDIA_TYPE_VIDEO:
            video_stream_i = i
            codec_ctx = format_ctx.streams[video_stream_i].codec
            print '\tfound %r at %d' % (codec_ctx.codec_name, video_stream_i)
            break
    else:
        print 'Could not find video stream.'
        return
    
    # Find the decoder for the video stream.
    codec = lib.avcodec_find_decoder(codec_ctx.codec_id)
    if codec == NULL:
        print 'Unsupported codec!'
        return
    print 'Codec is %r (%r)' % (codec.name, codec.long_name)
    
    print '"Opening" the codec.'
    errcheck(lib.avcodec_open2(codec_ctx, codec, &options))
    
    print 'Allocating frames.'
    cdef lib.AVFrame *raw_frame = lib.avcodec_alloc_frame()
    cdef lib.AVFrame *rgb_frame = lib.avcodec_alloc_frame()
    if raw_frame == NULL or rgb_frame == NULL:
        print 'Could not allocate frames.'
        return
    
    print 'Allocating buffer...'
    cdef int buffer_size = lib.avpicture_get_size(
        lib.PIX_FMT_RGBA,
        codec_ctx.width,
        codec_ctx.height,
    )
    print '\tof', buffer_size, 'bytes'
    cdef unsigned char *buffer = <unsigned char *>lib.av_malloc(buffer_size * sizeof(char))
    
    print 'Allocating SwsContext'
    cdef lib.SwsContext *sws_ctx = lib.sws_getContext(
        codec_ctx.width,
        codec_ctx.height,
        codec_ctx.pix_fmt,
        codec_ctx.width,
        codec_ctx.height,
        lib.PIX_FMT_RGBA,
        lib.SWS_BILINEAR,
        NULL,
        NULL,
        NULL
    )
    if sws_ctx == NULL:
        print 'Could not allocate.'
        return
     
    # Assign appropriate parts of buffer to image planes in pFrameRGB
    # Note that pFrameRGB is an AVFrame, but AVFrame is a superset
    # of AVPicture
    print 'Assigning buffer.'
    lib.avpicture_fill(
        <lib.AVPicture *>rgb_frame,
        buffer,
        lib.PIX_FMT_RGBA,
        codec_ctx.width,
        codec_ctx.height
    )
    
    print 'Reading packets...'
    cdef lib.AVPacket packet
    cdef int frame_i = 0
    cdef bint finished = False
    while True: #frame_i < 5:
        
        errcheck(lib.av_read_frame(format_ctx, &packet))
        
        # Is it from the right stream?
        # print '\tindex_stream', packet.stream_index
        if packet.stream_index != video_stream_i:
            continue
        
        # Decode the frame.
        errcheck(lib.avcodec_decode_video2(codec_ctx, raw_frame, &finished, &packet))
        if not finished:
            continue
        
        # print '\tfinished!'
        frame_i += 1
        
        lib.sws_scale(
            sws_ctx,
            raw_frame.data,
            raw_frame.linesize,
            0, # slice Y
            codec_ctx.height,
            rgb_frame.data,
            rgb_frame.linesize,
        )
        
        # Save the frame.
        # print raw_frame.linesize[0]
        # print raw_frame.width
        # print raw_frame.height
        
        # Create a Python buffer object so PIL doesn't need to copy the image.
        buf = lib.PyBuffer_FromMemory(rgb_frame.data[0], buffer_size)
        img = Image.frombuffer("RGBA", (codec_ctx.width, codec_ctx.height), buf, "raw", "RGBA", 0, 1)
        img.save('sandbox/frames/%04d.jpg' % frame_i, quality=20)
        
        lib.av_free_packet(&packet)
        
        
    print 'Done.'

