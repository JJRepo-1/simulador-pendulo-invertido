function calcular_ganancias(archivo_entrada, archivo_salida)
%CALCULAR_GANANCIAS  Ganancia de realimentacion por LMI (YALMIP + SeDuMi).
%
%   La llama Godot en modo batch:
%     matlab -batch "addpath('<carpeta>'); calcular_ganancias('entrada.json','salida.json')"
%
%   ENTRADA (JSON):
%     A      matriz n x n del modelo lineal (n = 4 regulador, n = 5 aumentado)
%     B      vector n x 1
%     alpha  parte real de los polos <= -alpha
%     beta   parte real de los polos >= -beta
%     ts     paso de Euler para revisar los polos discretos (opcional)
%
%   SALIDA (JSON):
%     ok, error, K (1 x n), polos_re, polos_im, polos_euler_abs, info
%
%   Misma formulacion que codigo4.m y codigo_seguimiento.m:
%     Q >= I,  L + L' <= -2*alpha*Q,  L + L' >= -2*beta*Q,  L = A*Q - B*Y
%     K = Y / Q

    salida = struct('ok', false, 'error', '', 'K', [], ...
        'polos_re', [], 'polos_im', [], 'polos_euler_abs', [], 'info', '');
    try
        datos = jsondecode(fileread(archivo_entrada));

        A = double(datos.A);
        B = double(datos.B(:));
        alpha = double(datos.alpha);
        beta = double(datos.beta);
        ts = 0.001;
        if isfield(datos, 'ts')
            ts = double(datos.ts);
        end
        n = size(A, 1);

        if size(A, 2) ~= n || numel(B) ~= n
            error('Dimensiones inconsistentes: A es %dx%d y B tiene %d elementos.', ...
                size(A, 1), size(A, 2), numel(B));
        end

        % Herramientas necesarias
        if exist('sdpvar', 'file') == 0
            error('No se encontro YALMIP en el path de MATLAB (addpath(genpath(...)) y savepath).');
        end
        if exist('sedumi', 'file') == 0
            error('No se encontro SeDuMi en el path de MATLAB (addpath(genpath(...)) y savepath).');
        end

        % Controlabilidad
        Co = B;
        for k = 1:n-1
            Co = [Co, A*Co(:, end)]; %#ok<AGROW>
        end
        if rank(Co) < n
            error('El sistema no es controlable (rango %d de %d).', rank(Co), n);
        end

        % LMI
        yalmip('clear');
        Q = sdpvar(n, n, 'symmetric');
        Y = sdpvar(1, n, 'full');
        L = A*Q - B*Y;
        restricciones = [Q >= eye(n), L + L' <= -2*alpha*Q, L + L' >= -2*beta*Q];
        opciones = sdpsettings('solver', 'sedumi', 'sedumi.eps', 1e-12, 'verbose', 0);
        diagnostico = optimize(restricciones, [], opciones);
        salida.info = diagnostico.info;

        Qvalor = value(Q);
        Yvalor = value(Y);
        if any(~isfinite(Qvalor(:))) || any(~isfinite(Yvalor(:))) || rcond(Qvalor) < 1e-12
            error('La solucion del LMI no es confiable (%s).', diagnostico.info);
        end

        K = Yvalor / Qvalor;
        polos = eig(A - B*K);
        polos_euler = eig(eye(n) + ts*(A - B*K));

        salida.ok = true;
        salida.K = K;
        salida.polos_re = real(polos).';
        salida.polos_im = imag(polos).';
        salida.polos_euler_abs = abs(polos_euler).';
    catch err
        salida.ok = false;
        salida.error = err.message;
    end

    fid = fopen(archivo_salida, 'w');
    fwrite(fid, jsonencode(salida), 'char');
    fclose(fid);
end
