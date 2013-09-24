#include "Base.h"
#include "RenderState.h"
#include "Node.h"
#include "Pass.h"
#include "Technique.h"
#include "Node.h"
#include "Scene.h"

// Render state override bits
#define RS_BLEND 1
#define RS_BLEND_FUNC 2
#define RS_CULL_FACE 4
#define RS_DEPTH_TEST 8
#define RS_DEPTH_WRITE 16
#define RS_DEPTH_FUNC 32
#define RS_CULL_FACE_SIDE 64
#define RS_COLOR_WRITE 128
#define RS_STENCIL_TEST 256 
#define RS_STENCIL_WRITE 512
#define RS_STENCIL_FUNC 1024
#define RS_STENCIL_OP 2048



namespace gameplay
{

RenderState::StateBlock* RenderState::StateBlock::_defaultState = NULL;
std::vector<RenderState::ResolveAutoBindingCallback> RenderState::_customAutoBindingResolvers;

RenderState::RenderState()
    : _nodeBinding(NULL), _state(NULL), _parent(NULL)
{
}

RenderState::~RenderState()
{
    SAFE_RELEASE(_state);

    // Destroy all the material parameters
    for (size_t i = 0, count = _parameters.size(); i < count; ++i)
    {
        SAFE_RELEASE(_parameters[i]);
    }
}

void RenderState::initialize()
{
    if (StateBlock::_defaultState == NULL)
    {
        StateBlock::_defaultState = StateBlock::create();
    }
}

void RenderState::finalize()
{
    SAFE_RELEASE(StateBlock::_defaultState);
}

void RenderState::registerAutoBindingResolver(ResolveAutoBindingCallback callback)
{
    _customAutoBindingResolvers.push_back(callback);
}

MaterialParameter* RenderState::getParameter(const char* name) const
{
    GP_ASSERT(name);

    // Search for an existing parameter with this name.
    MaterialParameter* param;
    for (size_t i = 0, count = _parameters.size(); i < count; ++i)
    {
        param = _parameters[i];
        GP_ASSERT(param);
        if (strcmp(param->getName(), name) == 0)
        {
            return param;
        }
    }

    // Create a new parameter and store it in our list.
    param = new MaterialParameter(name);
    _parameters.push_back(param);

    return param;
}

void RenderState::clearParameter(const char* name)
{
    for (size_t i = 0, count = _parameters.size(); i < count; ++i)
    {
        MaterialParameter* p = _parameters[i];
        if (p->_name == name)
        {
            _parameters.erase(_parameters.begin() + i);
            SAFE_RELEASE(p);
            break;
        }
    }
}

/**
 * @script{ignore}
 */
const char* autoBindingToString(RenderState::AutoBinding autoBinding)
{
    // NOTE: As new AutoBinding values are added, this switch statement must be updatd.
    switch (autoBinding)
    {
    case RenderState::NONE:
        return NULL;

    case RenderState::VIEW_MATRIX:
        return "VIEW_MATRIX";

    case RenderState::PROJECTION_MATRIX:
        return "PROJECTION_MATRIX";

    case RenderState::WORLD_VIEW_MATRIX:
        return "WORLD_VIEW_MATRIX";

    case RenderState::VIEW_PROJECTION_MATRIX:
        return "VIEW_PROJECTION_MATRIX";

    case RenderState::WORLD_VIEW_PROJECTION_MATRIX:
        return "WORLD_VIEW_PROJECTION_MATRIX";

    case RenderState::INVERSE_TRANSPOSE_WORLD_MATRIX:
        return "INVERSE_TRANSPOSE_WORLD_MATRIX";

    case RenderState::INVERSE_TRANSPOSE_WORLD_VIEW_MATRIX:
        return "INVERSE_TRANSPOSE_WORLD_VIEW_MATRIX";

    case RenderState::CAMERA_WORLD_POSITION:
        return "CAMERA_WORLD_POSITION";

    case RenderState::CAMERA_VIEW_POSITION:
        return "CAMERA_VIEW_POSITION";

    case RenderState::MATRIX_PALETTE:
        return "MATRIX_PALETTE";

    case RenderState::SCENE_AMBIENT_COLOR:
        return "SCENE_AMBIENT_COLOR";

    case RenderState::SCENE_LIGHT_COLOR:
        return "SCENE_LIGHT_COLOR";

    case RenderState::SCENE_LIGHT_DIRECTION:
        return "SCENE_LIGHT_DIRECTION";

    default:
        return "";
    }
}

void RenderState::setParameterAutoBinding(const char* name, AutoBinding autoBinding)
{
    setParameterAutoBinding(name, autoBindingToString(autoBinding));
}

void RenderState::setParameterAutoBinding(const char* name, const char* autoBinding)
{
    GP_ASSERT(name);
    GP_ASSERT(autoBinding);

    if (autoBinding == NULL)
    {
        // Remove an existing auto-binding
        std::map<std::string, std::string>::iterator itr = _autoBindings.find(name);
        if (itr != _autoBindings.end())
            _autoBindings.erase(itr);
    }
    else
    {
        // Add/update an auto-binding
        _autoBindings[name] = autoBinding;
    }

    // If we already have a node binding set, pass it to our handler now
    if (_nodeBinding)
    {
        applyAutoBinding(name, autoBinding);
    }
}

void RenderState::setStateBlock(StateBlock* state)
{
    if (_state != state)
    {
        SAFE_RELEASE(_state);

        _state = state;

        if (_state)
        {
            _state->addRef();
        }
    }
}

RenderState::StateBlock* RenderState::getStateBlock() const
{
    if (_state == NULL)
    {
        _state = StateBlock::create();
    }

    return _state;
}

void RenderState::setNodeBinding(Node* node)
{
    if (_nodeBinding != node)
    {
        _nodeBinding = node;

        if (_nodeBinding)
        {
            // Apply all existing auto-bindings using this node.
            std::map<std::string, std::string>::const_iterator itr = _autoBindings.begin();
            while (itr != _autoBindings.end())
            {
                applyAutoBinding(itr->first.c_str(), itr->second.c_str());
                ++itr;
            }
        }
    }
}

void RenderState::applyAutoBinding(const char* uniformName, const char* autoBinding)
{
    GP_ASSERT(_nodeBinding);

    MaterialParameter* param = getParameter(uniformName);
    GP_ASSERT(param);

    bool bound = false;

    // First attempt to resolve the binding using custom registered resolvers.
    if (_customAutoBindingResolvers.size() > 0)
    {
        for (size_t i = 0, count = _customAutoBindingResolvers.size(); i < count; ++i)
        {
            if (_customAutoBindingResolvers[i](autoBinding, _nodeBinding, param))
            {
                // Handled by custom auto binding resolver
                bound = true;
                break;
            }
        }
    }

    // Perform built-in resolution
    if (!bound)
    {
        bound = true;

        if (strcmp(autoBinding, "WORLD_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetWorldMatrix);
        }
        else if (strcmp(autoBinding, "VIEW_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetViewMatrix);
        }
        else if (strcmp(autoBinding, "PROJECTION_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetProjectionMatrix);
        }
        else if (strcmp(autoBinding, "WORLD_VIEW_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetWorldViewMatrix);
        }
        else if (strcmp(autoBinding, "VIEW_PROJECTION_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetViewProjectionMatrix);
        }
        else if (strcmp(autoBinding, "WORLD_VIEW_PROJECTION_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetWorldViewProjectionMatrix);
        }
        else if (strcmp(autoBinding, "INVERSE_TRANSPOSE_WORLD_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetInverseTransposeWorldMatrix);
        }
        else if (strcmp(autoBinding, "INVERSE_TRANSPOSE_WORLD_VIEW_MATRIX") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetInverseTransposeWorldViewMatrix);
        }
        else if (strcmp(autoBinding, "CAMERA_WORLD_POSITION") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetCameraWorldPosition);
        }
        else if (strcmp(autoBinding, "CAMERA_VIEW_POSITION") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetCameraViewPosition);
        }
        else if (strcmp(autoBinding, "MATRIX_PALETTE") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetMatrixPalette, &RenderState::autoBindingGetMatrixPaletteSize);
        }
        else if (strcmp(autoBinding, "SCENE_AMBIENT_COLOR") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetAmbientColor);
        }
        else if (strcmp(autoBinding, "SCENE_LIGHT_COLOR") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetLightColor);
        }
        else if (strcmp(autoBinding, "SCENE_LIGHT_DIRECTION") == 0)
        {
            param->bindValue(this, &RenderState::autoBindingGetLightDirection);
        }
        else
        {
            bound = false;
            GP_WARN("Unsupported auto binding type (%d).", autoBinding);
        }
    }

    if (bound)
    {
        // Mark parameter as an auto binding
        if (param->_type == MaterialParameter::METHOD && param->_value.method)
            param->_value.method->_autoBinding = true;
    }
}

const Matrix& RenderState::autoBindingGetWorldMatrix() const
{
    return _nodeBinding ? _nodeBinding->getWorldMatrix() : Matrix::identity();
}

const Matrix& RenderState::autoBindingGetViewMatrix() const
{
    return _nodeBinding ? _nodeBinding->getViewMatrix() : Matrix::identity();
}

const Matrix& RenderState::autoBindingGetProjectionMatrix() const
{
    return _nodeBinding ? _nodeBinding->getProjectionMatrix() : Matrix::identity();
}

const Matrix& RenderState::autoBindingGetWorldViewMatrix() const
{
    return _nodeBinding ? _nodeBinding->getWorldViewMatrix() : Matrix::identity();
}

const Matrix& RenderState::autoBindingGetViewProjectionMatrix() const
{
    return _nodeBinding ? _nodeBinding->getViewProjectionMatrix() : Matrix::identity();
}

const Matrix& RenderState::autoBindingGetWorldViewProjectionMatrix() const
{
    return _nodeBinding ? _nodeBinding->getWorldViewProjectionMatrix() : Matrix::identity();
}

const Matrix& RenderState::autoBindingGetInverseTransposeWorldMatrix() const
{
    return _nodeBinding ? _nodeBinding->getInverseTransposeWorldMatrix() : Matrix::identity();
}

const Matrix& RenderState::autoBindingGetInverseTransposeWorldViewMatrix() const
{
    return _nodeBinding ? _nodeBinding->getInverseTransposeWorldViewMatrix() : Matrix::identity();
}

Vector3 RenderState::autoBindingGetCameraWorldPosition() const
{
    return _nodeBinding ? _nodeBinding->getActiveCameraTranslationWorld() : Vector3::zero();
}

Vector3 RenderState::autoBindingGetCameraViewPosition() const
{
    return _nodeBinding ? _nodeBinding->getActiveCameraTranslationView() : Vector3::zero();
}

const Vector4* RenderState::autoBindingGetMatrixPalette() const
{
    Model* model = _nodeBinding ? _nodeBinding->getModel() : NULL;
    MeshSkin* skin = model ? model->getSkin() : NULL;
    return skin ? skin->getMatrixPalette() : NULL;
}

unsigned int RenderState::autoBindingGetMatrixPaletteSize() const
{
    Model* model = _nodeBinding ? _nodeBinding->getModel() : NULL;
    MeshSkin* skin = model ? model->getSkin() : NULL;
    return skin ? skin->getMatrixPaletteSize() : 0;
}

const Vector3& RenderState::autoBindingGetAmbientColor() const
{
    Scene* scene = _nodeBinding ? _nodeBinding->getScene() : NULL;
    return scene ? scene->getAmbientColor() : Vector3::zero();
}

const Vector3& RenderState::autoBindingGetLightColor() const
{
    Scene* scene = _nodeBinding ? _nodeBinding->getScene() : NULL;
    return scene ? scene->getLightColor() : Vector3::one();
}

const Vector3& RenderState::autoBindingGetLightDirection() const
{
    static Vector3 down(0, -1, 0);
    Scene* scene = _nodeBinding ? _nodeBinding->getScene() : NULL;
    return scene ? scene->getLightDirection() : down;
}

void RenderState::bind(Pass* pass)
{
    GP_ASSERT(pass);

    // Get the combined modified state bits for our RenderState hierarchy.
    long stateOverrideBits = _state ? _state->_bits : 0;
    RenderState* rs = _parent;
    while (rs)
    {
        if (rs->_state)
        {
            stateOverrideBits |= rs->_state->_bits;
        }
        rs = rs->_parent;
    }

    // Restore renderer state to its default, except for explicitly specified states
    StateBlock::restore(stateOverrideBits);

    // Apply parameter bindings and renderer state for the entire hierarchy, top-down.
    rs = NULL;
    Effect* effect = pass->getEffect();
    while ((rs = getTopmost(rs)))
    {
        for (size_t i = 0, count = rs->_parameters.size(); i < count; ++i)
        {
            GP_ASSERT(rs->_parameters[i]);
            rs->_parameters[i]->bind(effect);
        }

        if (rs->_state)
        {
            rs->_state->bindNoRestore();
        }
    }
}

RenderState* RenderState::getTopmost(RenderState* below)
{
    RenderState* rs = this;
    if (rs == below)
    {
        // Nothing below ourself.
        return NULL;
    }

    while (rs)
    {
        if (rs->_parent == below || rs->_parent == NULL)
        {
            // Stop traversing up here.
            return rs;
        }
        rs = rs->_parent;
    }
    
    return NULL;
}

void RenderState::cloneInto(RenderState* renderState, NodeCloneContext& context) const
{
    GP_ASSERT(renderState);

    // Clone parameters
    for (std::map<std::string, std::string>::const_iterator it = _autoBindings.begin(); it != _autoBindings.end(); ++it)
    {
        renderState->setParameterAutoBinding(it->first.c_str(), it->second.c_str());
    }
    for (std::vector<MaterialParameter*>::const_iterator it = _parameters.begin(); it != _parameters.end(); ++it)
    {
        const MaterialParameter* param = *it;
        GP_ASSERT(param);

        // If this parameter is a method binding auto binding, don't clone it - it will get setup automatically
        // via the cloned auto bindings instead.
        if (param->_type == MaterialParameter::METHOD && param->_value.method && param->_value.method->_autoBinding)
            continue;

        MaterialParameter* paramCopy = new MaterialParameter(param->getName());
        param->cloneInto(paramCopy);

        renderState->_parameters.push_back(paramCopy);
    }

    // Clone our state block
    if (_state)
    {
        _state->cloneInto(renderState->getStateBlock());
    }

    // Notes:
    // 1. _nodeBinding should not be set here, it should be set by the caller.
    // 2. _parent should not be set here, since it's set in the constructor of Technique and Pass.
}

RenderState::StateBlock::StateBlock()
    : _cullFaceEnabled(false), _depthTestEnabled(false), _depthWriteEnabled(true), _depthFunction(RenderState::DEPTH_LESS),
      _blendEnabled(false), _blendSrc(RenderState::BLEND_ONE), _blendDst(RenderState::BLEND_ZERO), _bits(0L),
	  _colorWriteEnabled(true), _stencilTestEnabled(false), _stencilWriteEnabled(true), _stencilFunction(STENCIL_ALWAYS), _stencilRef(0), _stencilMask(1), _stencilTestFailOp(STENCIL_KEEP), _depthTestFailOp(STENCIL_KEEP), _stencilAndDepthTestPassOp(STENCIL_KEEP)
{
}

RenderState::StateBlock::StateBlock(const StateBlock& copy)
{
    // Hidden
}

RenderState::StateBlock::~StateBlock()
{
}

RenderState::StateBlock* RenderState::StateBlock::create()
{
    return new RenderState::StateBlock();
}

void RenderState::StateBlock::bind()
{
    // When the public bind() is called with no RenderState object passed in,
    // we assume we are being called to bind the state of a single StateBlock,
    // irrespective of whether it belongs to a hierarchy of RenderStates.
    // Therefore, we call restore() here with only this StateBlock's override
    // bits to restore state before applying the new state.
    StateBlock::restore(_bits);

    bindNoRestore();
}

void RenderState::StateBlock::bindNoRestore()
{
    GP_ASSERT(_defaultState);

    // Update any state that differs from _defaultState and flip _defaultState bits
    if ((_bits & RS_BLEND) && (_blendEnabled != _defaultState->_blendEnabled))
    {
        if (_blendEnabled)
            GL_ASSERT( glEnable(GL_BLEND) );
        else
            GL_ASSERT( glDisable(GL_BLEND) );
        _defaultState->_blendEnabled = _blendEnabled;
    }
    if ((_bits & RS_BLEND_FUNC) && (_blendSrc != _defaultState->_blendSrc || _blendDst != _defaultState->_blendDst))
    {
        GL_ASSERT( glBlendFunc((GLenum)_blendSrc, (GLenum)_blendDst) );
        _defaultState->_blendSrc = _blendSrc;
        _defaultState->_blendDst = _blendDst;
    }
    if ((_bits & RS_CULL_FACE) && (_cullFaceEnabled != _defaultState->_cullFaceEnabled))
    {
        if (_cullFaceEnabled)
            GL_ASSERT( glEnable(GL_CULL_FACE) );
        else
            GL_ASSERT( glDisable(GL_CULL_FACE) );
        _defaultState->_cullFaceEnabled = _cullFaceEnabled;
    }
    if ((_bits & RS_CULL_FACE_SIDE) && (_cullFaceSide != _defaultState->_cullFaceSide))
    {
        GL_ASSERT( glCullFace((GLenum)_cullFaceSide) );
        _defaultState->_cullFaceSide = _cullFaceSide;
    }
    if ((_bits & RS_DEPTH_TEST) && (_depthTestEnabled != _defaultState->_depthTestEnabled))
    {
        if (_depthTestEnabled) 
            GL_ASSERT( glEnable(GL_DEPTH_TEST) );
        else 
            GL_ASSERT( glDisable(GL_DEPTH_TEST) );
        _defaultState->_depthTestEnabled = _depthTestEnabled;
    }
    if ((_bits & RS_DEPTH_WRITE) && (_depthWriteEnabled != _defaultState->_depthWriteEnabled))
    {
        GL_ASSERT( glDepthMask(_depthWriteEnabled ? GL_TRUE : GL_FALSE) );
        _defaultState->_depthWriteEnabled = _depthWriteEnabled;
    }
	if ((_bits & RS_COLOR_WRITE) && (_colorWriteEnabled != _defaultState->_colorWriteEnabled))
    {
        GL_ASSERT( glColorMask(_colorWriteEnabled ? GL_TRUE : GL_FALSE, _colorWriteEnabled ? GL_TRUE : GL_FALSE, _colorWriteEnabled ? GL_TRUE : GL_FALSE, _colorWriteEnabled ? GL_TRUE : GL_FALSE) );
        _defaultState->_colorWriteEnabled = _colorWriteEnabled;
    }
    if ((_bits & RS_DEPTH_FUNC) && (_depthFunction != _defaultState->_depthFunction))
    {
        GL_ASSERT( glDepthFunc((GLenum)_depthFunction) );
        _defaultState->_depthFunction = _depthFunction;
    }
	if ((_bits & RS_STENCIL_TEST) && (_stencilTestEnabled != _defaultState->_stencilTestEnabled))
    {
        if (_stencilTestEnabled) 
            GL_ASSERT( glEnable(GL_STENCIL_TEST) );
        else 
            GL_ASSERT( glDisable(GL_STENCIL_TEST) );
        _defaultState->_stencilTestEnabled = _stencilTestEnabled;
    }
	if ((_bits & RS_STENCIL_WRITE) && (_stencilWriteEnabled != _defaultState->_stencilWriteEnabled))
    {
        GL_ASSERT( glStencilMask(_stencilWriteEnabled ? GL_TRUE : GL_FALSE) );
        _defaultState->_stencilWriteEnabled = _stencilWriteEnabled;
    }

	if ((_bits & RS_STENCIL_FUNC) && (_stencilFunction != _defaultState->_stencilFunction || _stencilRef != _defaultState->_stencilRef || _stencilMask != _defaultState->_stencilMask))
    {
        GL_ASSERT( glStencilFunc((GLenum)_stencilFunction, _stencilRef, _stencilMask ));
        _defaultState->_stencilFunction = _stencilFunction;
		_defaultState->_stencilRef = _stencilRef;
		_defaultState->_stencilMask = _stencilMask;
    }
	if ((_bits & RS_STENCIL_OP) && (_stencilTestFailOp != _defaultState->_stencilTestFailOp || _depthTestFailOp != _defaultState->_depthTestFailOp || _stencilAndDepthTestPassOp != _defaultState->_stencilAndDepthTestPassOp))
    {
        GL_ASSERT( glStencilOp((GLenum)_stencilTestFailOp, (GLenum)_depthTestFailOp, (GLenum)_stencilAndDepthTestPassOp ));
        _defaultState->_stencilTestFailOp = _stencilTestFailOp;
		_defaultState->_depthTestFailOp = _depthTestFailOp;
		_defaultState->_stencilAndDepthTestPassOp = _stencilAndDepthTestPassOp;
    }

    _defaultState->_bits |= _bits;
}

void RenderState::StateBlock::restore(long stateOverrideBits)
{
    GP_ASSERT(_defaultState);

    // If there is no state to restore (i.e. no non-default state), do nothing.
    if (_defaultState->_bits == 0)
    {
        return;
    }

    // Restore any state that is not overridden and is not default
    if (!(stateOverrideBits & RS_BLEND) && (_defaultState->_bits & RS_BLEND))
    {
        GL_ASSERT( glDisable(GL_BLEND) );
        _defaultState->_bits &= ~RS_BLEND;
        _defaultState->_blendEnabled = false;
    }
    if (!(stateOverrideBits & RS_BLEND_FUNC) && (_defaultState->_bits & RS_BLEND_FUNC))
    {
        GL_ASSERT( glBlendFunc(GL_ONE, GL_ZERO) );
        _defaultState->_bits &= ~RS_BLEND_FUNC;
        _defaultState->_blendSrc = RenderState::BLEND_ONE;
        _defaultState->_blendDst = RenderState::BLEND_ZERO;
    }
    if (!(stateOverrideBits & RS_CULL_FACE) && (_defaultState->_bits & RS_CULL_FACE))
    {
        GL_ASSERT( glDisable(GL_CULL_FACE) );
        _defaultState->_bits &= ~RS_CULL_FACE;
        _defaultState->_cullFaceEnabled = false;
    }
    if (!(stateOverrideBits & RS_CULL_FACE_SIDE) && (_defaultState->_bits & RS_CULL_FACE_SIDE))
    {
        GL_ASSERT( glCullFace((GLenum)GL_BACK) );
        _defaultState->_bits &= ~RS_CULL_FACE_SIDE;
        _defaultState->_cullFaceSide = RenderState::CULL_FACE_SIDE_BACK;
    }
    if (!(stateOverrideBits & RS_DEPTH_TEST) && (_defaultState->_bits & RS_DEPTH_TEST))
    {
        GL_ASSERT( glDisable(GL_DEPTH_TEST) );
        _defaultState->_bits &= ~RS_DEPTH_TEST;
        _defaultState->_depthTestEnabled = false;
    }
    if (!(stateOverrideBits & RS_DEPTH_WRITE) && (_defaultState->_bits & RS_DEPTH_WRITE))
    {
        GL_ASSERT( glDepthMask(GL_TRUE) );
        _defaultState->_bits &= ~RS_DEPTH_WRITE;
        _defaultState->_depthWriteEnabled = true;
    }
	 if (!(stateOverrideBits & RS_COLOR_WRITE) && (_defaultState->_bits & RS_COLOR_WRITE))
    {
        GL_ASSERT( glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE) );
        _defaultState->_bits &= ~RS_COLOR_WRITE;
        _defaultState->_colorWriteEnabled = true;
    }
    if (!(stateOverrideBits & RS_DEPTH_FUNC) && (_defaultState->_bits & RS_DEPTH_FUNC))
    {
        GL_ASSERT( glDepthFunc((GLenum)GL_LESS) );
        _defaultState->_bits &= ~RS_DEPTH_FUNC;
        _defaultState->_depthFunction = RenderState::DEPTH_LESS;
    }
	if (!(stateOverrideBits & RS_STENCIL_TEST) && (_defaultState->_bits & RS_STENCIL_TEST))
    {
        GL_ASSERT( glDisable(GL_STENCIL_TEST) );
        _defaultState->_bits &= ~RS_STENCIL_TEST;
        _defaultState->_stencilTestEnabled = false;
    }
	 if (!(stateOverrideBits & RS_STENCIL_WRITE) && (_defaultState->_bits & RS_STENCIL_WRITE))
    {
        GL_ASSERT( glStencilMask(GL_TRUE) );
        _defaultState->_bits &= ~RS_STENCIL_WRITE;
        _defaultState->_stencilWriteEnabled = true;
    }
	if (!(stateOverrideBits & RS_STENCIL_FUNC) && (_defaultState->_bits & RS_STENCIL_FUNC))
    {
        GL_ASSERT( glStencilFunc((GLenum)GL_EQUAL,0,1 ) );
        _defaultState->_bits &= ~RS_STENCIL_FUNC;
        _defaultState->_stencilFunction = RenderState::STENCIL_EQUAL;
		_defaultState->_stencilRef = 0;
        _defaultState->_stencilMask = 1;
    }
	if (!(stateOverrideBits & RS_STENCIL_OP) && (_defaultState->_bits & RS_STENCIL_OP))
    {
        GL_ASSERT( glStencilOp((GLenum)GL_KEEP,GL_KEEP,GL_KEEP ) );
        _defaultState->_bits &= ~RS_STENCIL_OP;
        _defaultState->_stencilTestFailOp = RenderState::STENCIL_KEEP;
		_defaultState->_depthTestFailOp = RenderState::STENCIL_KEEP;
        _defaultState->_stencilAndDepthTestPassOp = RenderState::STENCIL_KEEP;
    }
}

void RenderState::StateBlock::enableDepthWrite()
{
    GP_ASSERT(_defaultState);

    // Internal method used by Game::clear() to restore depth writing before a
    // clear operation. This is necessary if the last code to draw before the
    // next frame leaves depth writing disabled.
    if (!_defaultState->_depthWriteEnabled)
    {
        GL_ASSERT( glDepthMask(GL_TRUE) );
        _defaultState->_bits &= ~RS_DEPTH_WRITE;
        _defaultState->_depthWriteEnabled = true;
    }
}

void RenderState::StateBlock::enableStencilWrite()
{
    GP_ASSERT(_defaultState);

    // Internal method used by Game::clear() to restore stencil writing before a
    // clear operation. This is necessary if the last code to draw before the
    // next frame leaves stencil writing disabled.
    if (!_defaultState->_stencilWriteEnabled)
    {
        GL_ASSERT( glStencilMask(GL_TRUE) );
        _defaultState->_bits &= ~RS_STENCIL_WRITE;
        _defaultState->_stencilWriteEnabled = true;
    }
}

void RenderState::StateBlock::enableColorWrite()
{
    GP_ASSERT(_defaultState);

    // Internal method used by Game::clear() to restore depth writing before a
    // clear operation. This is necessary if the last code to draw before the
    // next frame leaves depth writing disabled.
    if (!_defaultState->_colorWriteEnabled)
    {
        GL_ASSERT( glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE) );
        _defaultState->_bits &= ~RS_COLOR_WRITE;
        _defaultState->_colorWriteEnabled = true;
    }
}

void RenderState::StateBlock::cloneInto(StateBlock* state)
{
    GP_ASSERT(state);

    state->_cullFaceEnabled = _cullFaceEnabled;
    state->_depthTestEnabled = _depthTestEnabled;
    state->_depthWriteEnabled = _depthWriteEnabled;
    state->_depthFunction = _depthFunction;
	
	state->_stencilTestEnabled = _stencilTestEnabled;
    state->_stencilWriteEnabled = _stencilWriteEnabled;

	state->_stencilFunction = _stencilFunction;
	state->_stencilRef = _stencilRef;
	state->_stencilMask = _stencilMask;
	
	state->_stencilTestFailOp = _stencilTestFailOp;
	state->_depthTestFailOp = _depthTestFailOp;
	state->_stencilAndDepthTestPassOp = _stencilAndDepthTestPassOp;

	state->_colorWriteEnabled = _colorWriteEnabled;
    
	state->_blendEnabled = _blendEnabled;
    state->_blendSrc = _blendSrc;
    state->_blendDst = _blendDst;
    state->_cullFaceSide = _cullFaceSide;
    state->_bits = _bits;
}

static bool parseBoolean(const char* value)
{
    GP_ASSERT(value);

    if (strlen(value) == 4)
    {
        return (
            tolower(value[0]) == 't' &&
            tolower(value[1]) == 'r' &&
            tolower(value[2]) == 'u' &&
            tolower(value[3]) == 'e' );
    }

    return false;
}

static RenderState::Blend parseBlend(const char* value)
{
    GP_ASSERT(value);

    // Convert the string to uppercase for comparison.
    std::string upper(value);
    std::transform(upper.begin(), upper.end(), upper.begin(), (int(*)(int))toupper);
    if (upper == "ZERO")
        return RenderState::BLEND_ZERO;
    else if (upper == "ONE")
        return RenderState::BLEND_ONE;
    else if (upper == "SRC_COLOR")
        return RenderState::BLEND_SRC_COLOR;
    else if (upper == "ONE_MINUS_SRC_COLOR")
        return RenderState::BLEND_ONE_MINUS_SRC_COLOR;
    else if (upper == "DST_COLOR")
        return RenderState::BLEND_DST_COLOR;
    else if (upper == "ONE_MINUS_DST_COLOR")
        return RenderState::BLEND_ONE_MINUS_DST_COLOR;
    else if (upper == "SRC_ALPHA")
        return RenderState::BLEND_SRC_ALPHA;
    else if (upper == "ONE_MINUS_SRC_ALPHA")
        return RenderState::BLEND_ONE_MINUS_SRC_ALPHA;
    else if (upper == "DST_ALPHA")
        return RenderState::BLEND_DST_ALPHA;
    else if (upper == "ONE_MINUS_DST_ALPHA")
        return RenderState::BLEND_ONE_MINUS_DST_ALPHA;
    else if (upper == "CONSTANT_ALPHA")
        return RenderState::BLEND_CONSTANT_ALPHA;
    else if (upper == "ONE_MINUS_CONSTANT_ALPHA")
        return RenderState::BLEND_ONE_MINUS_CONSTANT_ALPHA;
    else if (upper == "SRC_ALPHA_SATURATE")
        return RenderState::BLEND_SRC_ALPHA_SATURATE;
    else
    {
        GP_ERROR("Unsupported blend value (%s). (Will default to BLEND_ONE if errors are treated as warnings)", value);
        return RenderState::BLEND_ONE;
    }
}

static RenderState::DepthFunction parseDepthFunc(const char* value)
{
    GP_ASSERT(value);

    // Convert string to uppercase for comparison
    std::string upper(value);
    std::transform(upper.begin(), upper.end(), upper.begin(), (int(*)(int))toupper);
    if (upper == "NEVER")
        return RenderState::DEPTH_NEVER;
    else if (upper == "LESS")
        return RenderState::DEPTH_LESS;
    else if (upper == "EQUAL")
        return RenderState::DEPTH_EQUAL;
    else if (upper == "LEQUAL")
        return RenderState::DEPTH_LEQUAL;
    else if (upper == "GREATER")
        return RenderState::DEPTH_GREATER;
    else if (upper == "NOTEQUAL")
        return RenderState::DEPTH_NOTEQUAL;
    else if (upper == "GEQUAL")
        return RenderState::DEPTH_GEQUAL;
    else if (upper == "ALWAYS")
        return RenderState::DEPTH_ALWAYS;
    else
    {
        GP_ERROR("Unsupported depth function value (%s). Will default to DEPTH_LESS if errors are treated as warnings)", value);
        return RenderState::DEPTH_LESS;
    }
}


static RenderState::StencilFunction parseStencilFunc(const char* value)
{
    GP_ASSERT(value);

    // Convert string to uppercase for comparison
    std::string upper(value);
    std::transform(upper.begin(), upper.end(), upper.begin(), (int(*)(int))toupper);
    if (upper == "NEVER")
        return RenderState::STENCIL_NEVER;
    else if (upper == "LESS")
        return RenderState::STENCIL_LESS;
    else if (upper == "EQUAL")
        return RenderState::STENCIL_EQUAL;
    else if (upper == "LEQUAL")
        return RenderState::STENCIL_LEQUAL;
    else if (upper == "GREATER")
        return RenderState::STENCIL_GREATER;
    else if (upper == "NOTEQUAL")
        return RenderState::STENCIL_NOTEQUAL;
    else if (upper == "GEQUAL")
        return RenderState::STENCIL_GEQUAL;
    else if (upper == "ALWAYS")
        return RenderState::STENCIL_ALWAYS;
    else
    {
        GP_ERROR("Unsupported depth function value (%s). Will default to DEPTH_LESS if errors are treated as warnings)", value);
        return RenderState::STENCIL_LESS;
    }
}

static RenderState::StencilFunction parseStencilRef(const char* value)
{
    GP_ASSERT(value);

    // Convert string to uppercase for comparison
    std::string upper(value);
    std::transform(upper.begin(), upper.end(), upper.begin(), (int(*)(int))toupper);
    if (upper == "NEVER")
        return RenderState::STENCIL_NEVER;
    else if (upper == "LESS")
        return RenderState::STENCIL_LESS;
    else if (upper == "EQUAL")
        return RenderState::STENCIL_EQUAL;
    else if (upper == "LEQUAL")
        return RenderState::STENCIL_LEQUAL;
    else if (upper == "GREATER")
        return RenderState::STENCIL_GREATER;
    else if (upper == "NOTEQUAL")
        return RenderState::STENCIL_NOTEQUAL;
    else if (upper == "GEQUAL")
        return RenderState::STENCIL_GEQUAL;
    else if (upper == "ALWAYS")
        return RenderState::STENCIL_ALWAYS;
    else
    {
        GP_ERROR("Unsupported depth function value (%s). Will default to DEPTH_LESS if errors are treated as warnings)", value);
        return RenderState::STENCIL_LESS;
    }
}

static RenderState::CullFaceSide parseCullFaceSide(const char* value)
{
    GP_ASSERT(value);

    // Convert string to uppercase for comparison
    std::string upper(value);
    std::transform(upper.begin(), upper.end(), upper.begin(), (int(*)(int))toupper);
    if (upper == "BACK")
        return RenderState::CULL_FACE_SIDE_BACK;
    else if (upper == "FRONT")
        return RenderState::CULL_FACE_SIDE_FRONT;
    else if (upper == "FRONT_AND_BACK")
        return RenderState::CULL_FACE_SIDE_FRONT_AND_BACK;
    else
    {
        GP_ERROR("Unsupported cull face side value (%s). Will default to BACK if errors are treated as warnings)", value);
        return RenderState::CULL_FACE_SIDE_BACK;
    }
}

static RenderState::StencilOp parseStencilTestFailOp(const char* value)
{
    GP_ASSERT(value);

    // Convert string to uppercase for comparison
    std::string upper(value);
    std::transform(upper.begin(), upper.end(), upper.begin(), (int(*)(int))toupper);
    if (upper == "KEEP")
        return RenderState::STENCIL_KEEP;
    else if (upper == "ZERO")
        return RenderState::STENCIL_ZERO;
    else if (upper == "REPLACE")
        return RenderState::STENCIL_REPLACE;
    else if (upper == "INCR")
        return RenderState::STENCIL_INCR;
    else if (upper == "INCR_WARP")
        return RenderState::STENCIL_INCR_WARP;
    else if (upper == "DECR")
        return RenderState::STENCIL_DECR;
    else if (upper == "DECR_WRAP")
        return RenderState::STENCIL_DECR_WRAP;
    else if (upper == "INVERT")
        return RenderState::STENCIL_INVERT;
    else
    {
        GP_ERROR("Unsupported stencilOp value (%s). Will default to STENCIL_KEEP if errors are treated as warnings)", value);
        return RenderState::STENCIL_KEEP;
    }
}

static RenderState::StencilOp parseDepthTestFailOp(const char* value)
{
	return parseStencilTestFailOp(value);
}

static RenderState::StencilOp parseStencilAndDepthTestPassOp(const char* value)
{
	return parseStencilTestFailOp(value);
}

void RenderState::StateBlock::setState(const char* name, const char* value)
{
    GP_ASSERT(name);

    if (strcmp(name, "blend") == 0)
    {
        setBlend(parseBoolean(value));
    }
    else if (strcmp(name, "blendSrc") == 0 || strcmp(name, "srcBlend") == 0 )   // Leaving srcBlend for backward compat.
    {
        setBlendSrc(parseBlend(value));
    }
    else if (strcmp(name, "blendDst") == 0 || strcmp(name, "dstBlend") == 0)    // // Leaving dstBlend for backward compat.
    {
        setBlendDst(parseBlend(value));
    }
    else if (strcmp(name, "cullFace") == 0)
    {
        setCullFace(parseBoolean(value));
    }
    else if (strcmp(name, "cullFaceSide") == 0)
    {
        setCullFaceSide(parseCullFaceSide(value));
    }
    else if (strcmp(name, "depthTest") == 0)
    {
        setDepthTest(parseBoolean(value));
    }
    else if (strcmp(name, "depthWrite") == 0)
    {
        setDepthWrite(parseBoolean(value));
    }
    else if (strcmp(name, "depthFunc") == 0)
    {
        setDepthFunction(parseDepthFunc(value));
    }
	else if (strcmp(name, "colorWrite") == 0)
    {
        setColorWrite(parseBoolean(value));
    }
/*	else if (strcmp(name, "stencilFunction") == 0)
    {
        setStencilFunction(parseStencilFunc(value));
    }
	else if (strcmp(name, "stencilRef") == 0)
    {
        setStencilRef(atoi(value));
    }
	else if (strcmp(name, "stencilMask") == 0)
    {
        setStencilMask(atoi(value));
    }
	else if (strcmp(name, "stencilTestFailOp") == 0)
    {
        setOpStencilTestFail(parseStencilTestFailOp(value));
    }
	else if (strcmp(name, "depthTestFailOp") == 0)
    {
        setOpDepthTestFail(parseDepthTestFailOp(value));
    }
	else if (strcmp(name, "stencilAndDepthTestPassOp") == 0)
    {
        setOpStencilAndDepthTestPass(parseStencilAndDepthTestPassOp(value));
    }
*/    else
    {
        GP_ERROR("Unsupported render state string '%s'.", name);
    }
}

void RenderState::StateBlock::setBlend(bool enabled)
{
    _blendEnabled = enabled;
    if (!enabled)
    {
        _bits &= ~RS_BLEND;
    }
    else
    {
        _bits |= RS_BLEND;
    }
}

void RenderState::StateBlock::setBlendSrc(Blend blend)
{
    _blendSrc = blend;
    if (_blendSrc == BLEND_ONE && _blendDst == BLEND_ZERO)
    {
        // Default blend func
        _bits &= ~RS_BLEND_FUNC;
    }
    else
    {
        _bits |= RS_BLEND_FUNC;
    }
}

void RenderState::StateBlock::setBlendDst(Blend blend)
{
    _blendDst = blend;
    if (_blendSrc == BLEND_ONE && _blendDst == BLEND_ZERO)
    {
        // Default blend func
        _bits &= ~RS_BLEND_FUNC;
    }
    else
    {
        _bits |= RS_BLEND_FUNC;
    }
}

void RenderState::StateBlock::setCullFace(bool enabled)
{
    _cullFaceEnabled = enabled;
    if (!enabled)
    {
        _bits &= ~RS_CULL_FACE;
    }
    else
    {
        _bits |= RS_CULL_FACE;
    }
}

void RenderState::StateBlock::setCullFaceSide(CullFaceSide side)
{
    _cullFaceSide = side;
    if (_cullFaceSide == CULL_FACE_SIDE_BACK)
    {
        // Default cull side
        _bits &= ~RS_CULL_FACE_SIDE;
    }
    else
    {
        _bits |= RS_CULL_FACE_SIDE;
    }
}

void RenderState::StateBlock::setDepthTest(bool enabled)
{
    _depthTestEnabled = enabled;
    if (!enabled)
    {
        _bits &= ~RS_DEPTH_TEST;
    }
    else
    {
        _bits |= RS_DEPTH_TEST;
    }
}

void RenderState::StateBlock::setDepthWrite(bool enabled)
{
    _depthWriteEnabled = enabled;
    if (enabled)
    {
        _bits &= ~RS_DEPTH_WRITE;
    }
    else
    {
        _bits |= RS_DEPTH_WRITE;
    }
}


void RenderState::StateBlock::setColorWrite(bool enabled)
{
    _colorWriteEnabled = enabled;
    if (enabled)
    {
        _bits &= ~RS_COLOR_WRITE;
    }
    else
    {
        _bits |= RS_COLOR_WRITE;
    }
}

void RenderState::StateBlock::setDepthFunction(DepthFunction func)
{
    _depthFunction = func;
    if (_depthFunction == DEPTH_LESS)
    {
        // Default depth function
        _bits &= ~RS_DEPTH_FUNC;
    }
    else
    {
        _bits |= RS_DEPTH_FUNC;
    }
}


void RenderState::StateBlock::setStencilWrite(bool enabled)
{
    _stencilWriteEnabled = enabled;
    if (enabled)
    {
        _bits &= ~RS_STENCIL_WRITE;
    }
    else
    {
        _bits |= RS_STENCIL_WRITE;
    }
}

void RenderState::StateBlock::setStencilTest(bool enabled)
{
    _stencilTestEnabled = enabled;
    if (!enabled)
    {
        _bits &= ~RS_STENCIL_TEST;
    }
    else
    {
        _bits |= RS_STENCIL_TEST;
    }
}


void RenderState::StateBlock::setStencilFunction(StencilFunction func, GLint ref, GLuint mask)
{
    _stencilFunction = func;
	_stencilRef = ref;
	_stencilMask = mask;

    if (_stencilFunction == STENCIL_EQUAL && _stencilRef == 0 && _stencilMask == 1)
    {
        // Default stencil function
        _bits &= ~RS_STENCIL_FUNC;
    }
    else
    {
        _bits |= RS_STENCIL_FUNC;
    }
}

/*void RenderState::StateBlock::setStencilRef( GLint ref)
{
    _stencilRef = ref;
    if (_stencilRef == 0)
    {
        // Default blend func
        _bits &= ~RS_STENCIL_FUNC;
    }
    else
    {
        _bits |= RS_STENCIL_FUNC;
    }
}

void RenderState::StateBlock::setStencilMask( GLuint ref)
{
    _stencilMask = ref;
    if (_stencilMask == 0)
    {
        // Default blend func
        _bits &= ~RS_STENCIL_FUNC;
    }
    else
    {
        _bits |= RS_STENCIL_FUNC;
    }
}
*/

void RenderState::StateBlock::setStencilOp(StencilOp sFail, StencilOp dpFail, StencilOp dpPass)
{

	 _stencilTestFailOp = sFail;
	 _depthTestFailOp = dpFail;
	 _stencilAndDepthTestPassOp = dpPass;

	  if (_stencilTestFailOp == GL_KEEP && _depthTestFailOp == GL_KEEP && _stencilAndDepthTestPassOp == GL_KEEP)
    {
        // Default stencil function
        _bits &= ~RS_STENCIL_OP;
    }
    else
    {
        _bits |= RS_STENCIL_OP;
    }

}

/*
void RenderState::StateBlock::setOpStencilTestFail(StencilOp sFail)
{
    _stencilTestFailOp = sFail;
    if (_stencilTestFailOp == GL_KEEP)
    {
        // Default stencil function
        _bits &= ~RS_STENCIL_OP;
    }
    else
    {
        _bits |= RS_STENCIL_OP;
    }
}

void RenderState::StateBlock::setOpDepthTestFail(StencilOp dpFail)
{
    _depthTestFailOp = dpFail;
    if (_depthTestFailOp == GL_KEEP)
    {
        // Default stencil function
        _bits &= ~RS_STENCIL_OP;
    }
    else
    {
        _bits |= RS_STENCIL_OP;
    }
}

void RenderState::StateBlock::setOpStencilAndDepthTestPass(StencilOp dpPass)
{
    _stencilAndDepthTestPassOp = dpPass;
    if (_stencilAndDepthTestPassOp == GL_KEEP)
    {
        // Default stencil function
        _bits &= ~RS_STENCIL_OP;
    }
    else
    {
        _bits |= RS_STENCIL_OP;
    }
}
*/
}
