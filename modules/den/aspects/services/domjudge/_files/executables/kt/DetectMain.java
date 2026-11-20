// DetectMain — prints which of the given classes has a public static void main; args[0] is the class directory.
// Part of the DOMjudge Programming Contest Jury System, licensed under the GNU GPL.

import java.lang.reflect.*;
import java.net.*;

public class DetectMain {
	public static void main ( String[] args ) {
		if ( args.length < 2 ) {
			System.err.println("Usage: java DetectMain <dir> <class1> "
			                   + "[ <class2> ... ]");
			System.exit(1);
			return;
		}

		URL dir;
		try {
			dir = new URL("file://" + args[0] + "/");
		} catch ( MalformedURLException e ) {
			System.err.println("Error: malformed directory '" + args[0] + "'");
			System.exit(1);
			return;
		}
		ClassLoader cl = new URLClassLoader( new URL[] { dir } );

		String result = null;
		for ( int i = 1; i < args.length; i++) {
			String arg = args[i];

			Class<?> c;
			try {
				c = Class.forName(arg, false, cl);
			} catch ( ClassNotFoundException e ) {
				System.err.println("Error: class '" + arg + "' not found.");
				System.exit(1);
				return;
			}

			Method mainMethod;
			try {
				mainMethod = c.getDeclaredMethod("main", args.getClass());
			} catch ( NoSuchMethodException e ) {
				continue;
			}

			if ( Modifier.isStatic(mainMethod.getModifiers())
			   && Modifier.isPublic(mainMethod.getModifiers())
			   && mainMethod.getReturnType().equals(Void.TYPE) ) {
				if ( result != null ) {
					System.err.println("Warning: found another 'main' in '"
					                   + arg + "'");
				}
				else {
					System.err.println("Info: using 'main' from '" + arg + "'");
					result = arg;
				}
			}
		}

		if ( result == null ) {
			System.err.println("Error: no 'main' found in any class file.");
			System.exit(1);
			return;
		}

		System.out.println(result);
	}
}
