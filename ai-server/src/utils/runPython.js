const { spawn } = require('child_process');

/**
 * @param {string} pythonCmd 
 * @param {string} scriptPath 
 * @param {string[]} args 
 */
function runPython(pythonCmd, scriptPath, args = []) {
  return new Promise((resolve, reject) => {
    const extra = (process.env.PYTHON_ARGS || '').trim();
    const extraArgs = extra ? extra.split(/\s+/) : [];

    const proc = spawn(pythonCmd, [...extraArgs, scriptPath, ...args], {
      windowsHide: true,
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (d) => (stdout += d.toString()));
    proc.stderr.on('data', (d) => (stderr += d.toString()));

    proc.on('error', (err) => reject(err));

    proc.on('close', (code) => {
      if (code !== 0) {
        return reject(
          new Error(
            `Python exited with code ${code}. stderr: ${stderr || '(empty)'}`,
          ),
        );
      }

      const trimmed = stdout.trim();
      if (!trimmed) {
        return reject(
          new Error(
            `Python returned empty stdout. stderr: ${stderr || '(empty)'}`,
          ),
        );
      }

      try {
        const parsed = JSON.parse(trimmed);
        resolve(parsed);
      } catch (e) {
        reject(
          new Error(
            `Failed to parse Python JSON.\nstdout: ${trimmed}\nstderr: ${stderr || '(empty)'}`,
          ),
        );
      }
    });
  });
}

module.exports = { runPython };
