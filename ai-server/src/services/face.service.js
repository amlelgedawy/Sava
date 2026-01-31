const path = require('path');
const { runPython } = require('../utils/runPython');

function mapFaceResult(result) {
  if (result.status === 'match') {
    return [
      {
        type: 'FACE',
        confidence:
          typeof result.confidence === 'number' ? result.confidence : 1,
        payload: {
          recognized: true,
          name_key: result.name_key,
        },
      },
    ];
  }

  if (result.status === 'no_face') {
    return []; 
  }

  if (result.status === 'no_match') {
    return [
      {
        type: 'FACE',
        confidence:
          typeof result.confidence === 'number' ? result.confidence : 1,
        payload: {
          recognized: false,
        },
      },
    ];
  }

  return [];
}

async function analyzeFace(framePath) {
  const pythonCmd = process.env.PYTHON_PATH || 'python';
  const scriptPath = path.join(process.cwd(), 'python', 'face_ai.py');

  const result = await runPython(pythonCmd, scriptPath, [framePath]);

  const events = mapFaceResult(result);

  return { result, events };
}

module.exports = { analyzeFace };
